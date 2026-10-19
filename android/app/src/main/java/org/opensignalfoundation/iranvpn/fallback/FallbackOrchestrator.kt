package org.opensignalfoundation.iranvpn.fallback

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.selects.select
import kotlinx.coroutines.withTimeoutOrNull
import org.opensignalfoundation.iranvpn.model.PathConfig
import org.opensignalfoundation.iranvpn.model.PathKind
import org.opensignalfoundation.iranvpn.model.ServerList

/**
 * Races paths in parallel on Dispatchers.IO. First Success wins; other runners disconnect.
 */
class FallbackOrchestrator(
    private val serverList: ServerList,
    private val pathRunners: Map<PathKind, PathRunner>,
) {
    private val _state = MutableStateFlow(FallbackState())
    val state: Flow<FallbackState> = _state.asStateFlow()

    private val _events = MutableStateFlow<FallbackEvent?>(null)
    val events: Flow<FallbackEvent?> = _events.asStateFlow()

    private val defaultOrder = listOf(PathKind.PSIPHON, PathKind.XRAY)
    private val raceBudgetMs = 8_000L

    private fun raceCandidates(): List<Pair<Int, PathConfig>> {
        return serverList.paths.mapIndexedNotNull { i, path ->
            val kind = path.kind()
            if (kind !in defaultOrder) return@mapIndexedNotNull null
            if (pathRunners[kind] == null) return@mapIndexedNotNull null
            i to path
        }.sortedBy { (_, path) ->
            defaultOrder.indexOf(path.kind()).let { if (it < 0) Int.MAX_VALUE else it }
        }.take(3)
    }

    suspend fun run(): Result<PathKind> = coroutineScope {
        val toRace = raceCandidates()
        if (toRace.isEmpty()) {
            _events.value = FallbackEvent.AllPathsFailed
            return@coroutineScope Result.failure(Exception("no paths configured"))
        }

        data class Attempt(val idx: Int, val kind: PathKind, val runner: PathRunner, val result: PathResult)

        val jobs = toRace.map { (idx, path) ->
            async(Dispatchers.IO) {
                val kind = path.kind()
                val runner = pathRunners.getValue(kind)
                _events.value = FallbackEvent.Connecting(pathKind = kind, index = idx)
                val result = try {
                    withTimeoutOrNull(raceBudgetMs) {
                        runner.connect(path)
                    } ?: PathResult.Failure("timeout ${raceBudgetMs}ms")
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    PathResult.Failure(e.message ?: "error")
                }
                Attempt(idx, kind, runner, result)
            }
        }.toMutableList()

        val failures = mutableListOf<String>()
        while (jobs.isNotEmpty()) {
            val attempt = select<Attempt> {
                jobs.forEach { job ->
                    job.onAwait { it }
                }
            }
            jobs.removeAll { it.isCompleted }

            when (val result = attempt.result) {
                is PathResult.Success -> {
                    for ((i, path) in toRace) {
                        if (i != attempt.idx) {
                            val other = pathRunners[path.kind()]
                            if (other != null && other !== attempt.runner) {
                                other.disconnect()
                            }
                        }
                    }
                    jobs.forEach { it.cancel() }
                    _state.value = FallbackState(
                        activePathIndex = attempt.idx,
                        activePathKind = attempt.kind,
                        connectionEstablished = true,
                        failureCount = 0,
                    )
                    _events.value = FallbackEvent.Connected(pathKind = attempt.kind, index = attempt.idx)
                    return@coroutineScope Result.success(attempt.kind)
                }
                is PathResult.Failure -> {
                    failures.add("${attempt.kind}: ${result.error}")
                    _events.value = FallbackEvent.PathFailed(attempt.kind, attempt.idx, result.error)
                    if (result.error.startsWith("timeout")) {
                        attempt.runner.disconnect()
                    }
                }
            }
        }

        _state.value = FallbackState(failureCount = failures.size)
        _events.value = FallbackEvent.AllPathsFailed
        Result.failure(Exception("all paths failed: ${failures.joinToString("; ")}"))
    }

    suspend fun disconnect(runner: PathRunner?) {
        runner?.disconnect()
        _state.value = FallbackState()
    }
}

data class FallbackState(
    val activePathIndex: Int? = null,
    val activePathKind: PathKind? = null,
    val connectionEstablished: Boolean = false,
    val failureCount: Int = 0,
)

sealed class FallbackEvent {
    data class Connecting(val pathKind: PathKind, val index: Int) : FallbackEvent()
    data class Connected(val pathKind: PathKind, val index: Int) : FallbackEvent()
    data class PathFailed(val pathKind: PathKind, val index: Int, val error: String) : FallbackEvent()
    object AllPathsFailed : FallbackEvent()
}

sealed class PathResult {
    object Success : PathResult()
    data class Failure(val error: String) : PathResult()
}
