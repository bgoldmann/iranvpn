package org.opensignalfoundation.iranvpn.tunnel

import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.InetSocketAddress
import java.net.Proxy
import java.net.Socket
import java.net.URL
import java.util.concurrent.TimeUnit
import javax.net.ssl.HttpsURLConnection

/**
 * Probe gate: a path is "connected" only after a known-token fetch through the local SOCKS port.
 * "Process still running" is not connectivity.
 */
object ConnectivityProbe {

    /** Default probe: Cloudflare trace returns "warp=off" / "ip=" lines over HTTPS. */
    const val DEFAULT_PROBE_URL = "https://www.cloudflare.com/cdn-cgi/trace"
    const val DEFAULT_TOKEN_SUBSTRING = "ip="
    private const val TIMEOUT_MS = 8_000

    private data class ProbeTarget(
        val url: String,
        val token: String,
        val expectedStatus: Int?,
        val timeoutMs: Int,
    )

    // Keep in sync with core/src/probe.rs. Later targets are not Cloudflare:
    // 1.1.1.1 and cp.cloudflare.com fail together with the primary.
    private val probeTargets = listOf(
        ProbeTarget(DEFAULT_PROBE_URL, DEFAULT_TOKEN_SUBSTRING, null, TIMEOUT_MS),
        ProbeTarget("https://www.gstatic.com/generate_204", "", 204, 4_000),
        ProbeTarget("https://detectportal.firefox.com/success.txt", "success", null, 4_000),
    )

    /**
     * Fetch [url] via SOCKS5 at 127.0.0.1:[socksPort] and require [token] in the body
     * (empty [token] = any 2xx success, unless [expectedStatus] is set).
     */
    fun probeThroughSocks(
        socksPort: Int,
        url: String = DEFAULT_PROBE_URL,
        token: String = DEFAULT_TOKEN_SUBSTRING,
        expectedStatus: Int? = null,
        timeoutMs: Int = TIMEOUT_MS,
    ): Result<Unit> {
        if (socksPort <= 0) {
            return Result.failure(IllegalStateException("no SOCKS port"))
        }
        return runCatching {
            val proxy = Proxy(Proxy.Type.SOCKS, InetSocketAddress("127.0.0.1", socksPort))
            val conn = (URL(url).openConnection(proxy) as HttpsURLConnection).apply {
                connectTimeout = timeoutMs
                readTimeout = timeoutMs
                requestMethod = "GET"
                instanceFollowRedirects = true
                setRequestProperty("User-Agent", "IranVPN/1.0")
                setRequestProperty("Accept-Encoding", "identity")
            }
            try {
                conn.connect()
                val code = conn.responseCode
                if (expectedStatus != null) {
                    if (code != expectedStatus) error("probe HTTP $code, want $expectedStatus")
                } else if (code !in 200..299) {
                    error("probe HTTP $code")
                }
                if (token.isNotEmpty()) {
                    val body = BufferedReader(InputStreamReader(conn.inputStream)).use { it.readText() }
                    if (!body.contains(token)) {
                        error("probe token missing")
                    }
                }
            } finally {
                conn.disconnect()
            }
        }
    }

    /** Cloudflare trace, then non-Cloudflare checks, so a CF-only failure does not fail Connect. */
    fun probeDefault(socksPort: Int): Result<Unit> {
        var last: Result<Unit> = Result.failure(IllegalStateException("no probes"))
        for (t in probeTargets) {
            last = probeThroughSocks(socksPort, t.url, t.token, t.expectedStatus, t.timeoutMs)
            if (last.isSuccess) return last
        }
        return last
    }

    /** Quick TCP check that SOCKS is accepting connections. */
    fun socksAccepting(socksPort: Int, timeoutMs: Int = 2_000): Boolean {
        if (socksPort <= 0) return false
        return try {
            Socket().use { s ->
                s.connect(InetSocketAddress("127.0.0.1", socksPort), timeoutMs)
                true
            }
        } catch (_: Exception) {
            false
        }
    }

    fun awaitSocks(socksPortProvider: () -> Int, timeoutMs: Long = 15_000): Int {
        val deadline = System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(timeoutMs)
        while (System.nanoTime() < deadline) {
            val port = socksPortProvider()
            if (socksAccepting(port)) return port
            Thread.sleep(200)
        }
        return 0
    }
}
