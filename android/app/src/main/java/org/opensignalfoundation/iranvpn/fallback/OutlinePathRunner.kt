package org.opensignalfoundation.iranvpn.fallback

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import org.opensignalfoundation.iranvpn.model.PathConfig
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

/**
 * Outline / Shadowsocks via sing-box when available (ss:// access key → SOCKS).
 */
class OutlinePathRunner(private val context: Context) : PathRunner, SocksProxyProvider {
    private val processRef = AtomicReference<Process?>(null)
    private var socksPort: Int = 10810

    override fun connect(config: PathConfig): PathResult {
        if (config !is PathConfig.OutlineConfig) return PathResult.Failure("wrong config type")
        val key = config.accessKey.trim()
        if (!key.startsWith("ss://", ignoreCase = true)) {
            return PathResult.Failure("Outline access key must be ss://…")
        }
        val binary = AssetBinary.findOrExtract(
            context,
            listOf("sing-box/\$ABI/sing-box", "sing-box/sing-box"),
            "sing-box",
        ) ?: return PathResult.Failure(
            "Outline path needs sing-box binary (assets/sing-box/<abi>/sing-box)",
        )

        val json = singBoxFromSs(key, socksPort)
            ?: return PathResult.Failure("Could not parse ss:// access key")

        val cfg = java.io.File(context.noBackupFilesDir, "outline/cfg_${System.nanoTime()}.json").apply {
            parentFile?.mkdirs()
            writeText(json)
        }
        return try {
            val p = ProcessBuilder(binary, "run", "-c", cfg.absolutePath)
                .directory(context.cacheDir)
                .redirectErrorStream(true)
                .start()
            processRef.set(p)
            val exited = p.waitFor(4, TimeUnit.SECONDS)
            if (exited) {
                val err = p.inputStream.bufferedReader().readText().take(240)
                PathResult.Failure("outline/sing-box exited: $err")
            } else {
                PathResult.Success
            }
        } catch (e: Exception) {
            PathResult.Failure("outline: ${e.message}")
        } finally {
            cfg.delete()
        }
    }

    override fun disconnect() {
        processRef.getAndSet(null)?.destroyForcibly()
    }

    override fun getLocalSocksPort(): Int = socksPort

    override fun supportsUdp(): Boolean = true

    companion object {
        fun isAvailable(context: Context): Boolean = SingBoxPathRunner.isAvailable(context)

        /** Minimal sing-box config: socks inbound + shadowsocks outbound from ss:// URI. */
        fun singBoxFromSs(ssUri: String, socksPort: Int): String? {
            // Prefer letting sing-box parse legacy URI via outbound type shadowsocks + server fields.
            // SIP002: ss://base64(method:password)@host:port or ss://base64(method:password@host:port)
            val raw = ssUri.removePrefix("ss://").removePrefix("SS://")
            val hash = raw.indexOf('#')
            val main = if (hash >= 0) raw.substring(0, hash) else raw
            val at = main.lastIndexOf('@')
            val method: String
            val password: String
            val host: String
            val port: Int
            if (at > 0) {
                val userInfoB64 = main.substring(0, at)
                var hostPort = main.substring(at + 1)
                val q = hostPort.indexOf('?')
                if (q >= 0) hostPort = hostPort.substring(0, q)
                val decoded = decodeB64(userInfoB64) ?: return null
                val colon = decoded.indexOf(':')
                if (colon < 0) return null
                method = decoded.substring(0, colon)
                password = decoded.substring(colon + 1)
                val hp = splitHostPort(hostPort) ?: return null
                host = hp.first
                port = hp.second
            } else {
                val decoded = decodeB64(main) ?: return null
                // method:password@host:port
                val at2 = decoded.lastIndexOf('@')
                if (at2 < 0) return null
                val user = decoded.substring(0, at2)
                var hostPort = decoded.substring(at2 + 1)
                val q = hostPort.indexOf('?')
                if (q >= 0) hostPort = hostPort.substring(0, q)
                val colon = user.indexOf(':')
                if (colon < 0) return null
                method = user.substring(0, colon)
                password = user.substring(colon + 1)
                val hp = splitHostPort(hostPort) ?: return null
                host = hp.first
                port = hp.second
            }

            return JSONObject()
                .put(
                    "inbounds",
                    JSONArray().put(
                        JSONObject()
                            .put("type", "socks")
                            .put("tag", "socks-in")
                            .put("listen", "127.0.0.1")
                            .put("listen_port", socksPort),
                    ),
                )
                .put(
                    "outbounds",
                    JSONArray().put(
                        JSONObject()
                            .put("type", "shadowsocks")
                            .put("tag", "proxy")
                            .put("server", host)
                            .put("server_port", port)
                            .put("method", method)
                            .put("password", password),
                    ),
                )
                .toString()
        }

        private fun decodeB64(s: String): String? {
            return try {
                val pad = when (s.length % 4) {
                    2 -> "=="
                    3 -> "="
                    else -> ""
                }
                String(android.util.Base64.decode(s + pad, android.util.Base64.URL_SAFE or android.util.Base64.DEFAULT))
            } catch (_: Exception) {
                null
            }
        }

        private fun splitHostPort(hostPort: String): Pair<String, Int>? {
            if (hostPort.startsWith("[")) {
                val end = hostPort.indexOf(']')
                if (end < 0) return null
                val host = hostPort.substring(1, end)
                val after = hostPort.substring(end + 1)
                if (!after.startsWith(":")) return null
                val port = after.substring(1).toIntOrNull() ?: return null
                return host to port
            }
            val colon = hostPort.lastIndexOf(':')
            if (colon < 0) return null
            return hostPort.substring(0, colon) to (hostPort.substring(colon + 1).toIntOrNull() ?: return null)
        }
    }
}
