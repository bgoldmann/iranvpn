package org.opensignalfoundation.iranvpn.fallback

import android.content.Context
import org.opensignalfoundation.iranvpn.model.PathConfig
import java.io.File
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

/**
 * sing-box multi-protocol path (Hysteria2, Reality, TUIC, SS2022, …).
 * Place binary at `assets/sing-box/$ABI/sing-box` or `assets/sing-box/sing-box`.
 */
class SingBoxPathRunner(private val context: Context) : PathRunner, SocksProxyProvider {
    private val processRef = AtomicReference<Process?>(null)
    private var socksPort: Int = DEFAULT_SOCKS

    override fun connect(config: PathConfig): PathResult {
        if (config !is PathConfig.SingBoxConfig) return PathResult.Failure("wrong config type")
        val binary = AssetBinary.findOrExtract(
            context,
            listOf("sing-box/\$ABI/sing-box", "sing-box/sing-box"),
            "sing-box",
        ) ?: return PathResult.Failure("sing-box binary missing — add assets/sing-box/<abi>/sing-box")

        var json = config.configJson.trim()
        if (json.startsWith("hy2://") || json.startsWith("hysteria2://")) {
            json = hy2ToSingBoxJson(json, DEFAULT_SOCKS)
                ?: return PathResult.Failure("Could not parse Hysteria2 share link")
        }
        if (json.isBlank() || json == "{}") {
            val sub = config.subscriptionUrl
                ?: return PathResult.Failure("sing-box needs config_json, hy2:// link, or subscription_url")
            return PathResult.Failure("sing-box subscription fetch not wired yet: $sub")
        }
        socksPort = extractSocksPort(json) ?: DEFAULT_SOCKS
        json = ensureSocksInbound(json, socksPort)

        val cfg = File(context.noBackupFilesDir, "singbox/cfg_${System.nanoTime()}.json").apply {
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
                p.destroyForcibly()
                PathResult.Failure("sing-box exited: $err")
            } else {
                PathResult.Success
            }
        } catch (e: Exception) {
            PathResult.Failure("sing-box: ${e.message}")
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
        private const val DEFAULT_SOCKS = 10809

        fun isAvailable(context: Context): Boolean =
            AssetBinary.hasAny(context, listOf("sing-box/\$ABI/sing-box", "sing-box/sing-box"))

        private fun extractSocksPort(json: String): Int? {
            val m = Regex(""""listen_port"\s*:\s*(\d+)""").find(json)
            return m?.groupValues?.getOrNull(1)?.toIntOrNull()
        }

        private fun ensureSocksInbound(json: String, port: Int): String {
            if (json.contains("\"socks\"", ignoreCase = true) ||
                json.contains("\"mixed\"", ignoreCase = true)
            ) {
                return json
            }
            // Prepend a socks inbound so ConnectivityProbe can reach 127.0.0.1:port.
            return try {
                val root = org.json.JSONObject(json)
                val inbounds = root.optJSONArray("inbounds") ?: org.json.JSONArray()
                val socks = org.json.JSONObject()
                    .put("type", "socks")
                    .put("tag", "socks-in")
                    .put("listen", "127.0.0.1")
                    .put("listen_port", port)
                val merged = org.json.JSONArray().put(socks)
                for (i in 0 until inbounds.length()) {
                    merged.put(inbounds.get(i))
                }
                root.put("inbounds", merged).toString()
            } catch (_: Exception) {
                json
            }
        }

        /** hy2://auth@host:port?sni=…&obfs=salamander&obfs-password=…#name */
        fun hy2ToSingBoxJson(link: String, socksPort: Int): String? {
            val raw = link.removePrefix("hysteria2://").removePrefix("hy2://")
            val hash = raw.indexOf('#')
            val main = if (hash >= 0) raw.substring(0, hash) else raw
            val at = main.indexOf('@')
            if (at < 0) return null
            val password = java.net.URLDecoder.decode(main.substring(0, at), "UTF-8")
            val rest = main.substring(at + 1)
            val q = rest.indexOf('?')
            val hostPort = if (q >= 0) rest.substring(0, q) else rest
            val query = if (q >= 0) rest.substring(q + 1) else ""
            val (host, port) = splitHostPort(hostPort) ?: return null
            val params = query.split('&').mapNotNull { part ->
                val eq = part.indexOf('=')
                if (eq < 0) null
                else java.net.URLDecoder.decode(part.substring(0, eq), "UTF-8") to
                    java.net.URLDecoder.decode(part.substring(eq + 1), "UTF-8")
            }.toMap()

            val outbound = org.json.JSONObject()
                .put("type", "hysteria2")
                .put("tag", "proxy")
                .put("server", host)
                .put("server_port", port)
                .put("password", password)
            params["sni"]?.let { outbound.put("tls", org.json.JSONObject().put("enabled", true).put("server_name", it)) }
            if (params["obfs"] != null) {
                outbound.put(
                    "obfs",
                    org.json.JSONObject()
                        .put("type", params["obfs"])
                        .put("password", params["obfs-password"] ?: ""),
                )
            }
            return org.json.JSONObject()
                .put(
                    "inbounds",
                    org.json.JSONArray().put(
                        org.json.JSONObject()
                            .put("type", "socks")
                            .put("tag", "socks-in")
                            .put("listen", "127.0.0.1")
                            .put("listen_port", socksPort),
                    ),
                )
                .put("outbounds", org.json.JSONArray().put(outbound))
                .toString()
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
            val host = hostPort.substring(0, colon)
            val port = hostPort.substring(colon + 1).toIntOrNull() ?: return null
            return host to port
        }
    }
}
