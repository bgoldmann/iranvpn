package org.opensignalfoundation.iranvpn.model

import android.util.Base64
import org.json.JSONArray
import org.json.JSONObject
import java.net.URLDecoder

/**
 * Parse VLESS / VMess / Trojan share links into Xray JSON configs.
 * Supports REALITY (security=reality) and xHTTP / ws / grpc transports.
 */
object ShareLinkParser {

    fun parse(link: String): PathConfig? {
        val trimmed = link.trim()
        return when {
            trimmed.startsWith("vless://") -> PathConfig.XrayConfig(
                configJson = trimmed,
                subscriptionUrl = null,
            )
            trimmed.startsWith("vmess://") -> PathConfig.XrayConfig(
                configJson = trimmed,
                subscriptionUrl = null,
            )
            trimmed.startsWith("trojan://") -> PathConfig.XrayConfig(
                configJson = trimmed,
                subscriptionUrl = null,
            )
            trimmed.startsWith("ss://", ignoreCase = true) ->
                PathConfig.OutlineConfig(accessKey = trimmed)
            trimmed.startsWith("hy2://") || trimmed.startsWith("hysteria2://") ->
                PathConfig.SingBoxConfig(configJson = trimmed, subscriptionUrl = null)
            trimmed.trimStart().startsWith("{") && trimmed.contains("\"inbounds\"") ->
                PathConfig.SingBoxConfig(configJson = trimmed, subscriptionUrl = null)
            trimmed.contains("[Interface]", ignoreCase = true) &&
                (trimmed.contains("Jc") || trimmed.contains("Awg") || trimmed.contains("Amnezia", ignoreCase = true)) ->
                PathConfig.AmneziaWgConfig(config = trimmed)
            trimmed.contains("[Interface]", ignoreCase = true) ->
                PathConfig.RostamConfig(wireguardConfig = trimmed)
            trimmed.startsWith("snowflake ") || trimmed.startsWith("webtunnel ") ||
                trimmed.startsWith("obfs4 ") || trimmed.startsWith("Bridge ") ->
                PathConfig.TorConfig(bridges = listOf(trimmed.removePrefix("Bridge ").trim()))
            trimmed.startsWith("http://") || trimmed.startsWith("https://") ->
                PathConfig.XrayConfig(configJson = "{}", subscriptionUrl = trimmed)
            else -> null
        }
    }

    fun toXrayJson(shareLink: String, socksPort: Int = 10808): String? {
        val link = shareLink.trim()
        return when {
            link.startsWith("vless://") -> vlessToJson(link, socksPort)
            link.startsWith("vmess://") -> vmessToJson(link, socksPort)
            link.startsWith("trojan://") -> trojanToJson(link, socksPort)
            link.trimStart().startsWith("{") -> link
            else -> null
        }
    }

    private fun vlessToJson(link: String, socksPort: Int): String? {
        // vless://uuid@host:port?encryption=none&security=reality&sni=...&fp=chrome&pbk=...&sid=...&type=tcp#name
        val withoutScheme = link.removePrefix("vless://")
        val hashIdx = withoutScheme.indexOf('#')
        val main = if (hashIdx >= 0) withoutScheme.substring(0, hashIdx) else withoutScheme
        val at = main.indexOf('@')
        if (at < 0) return null
        val uuid = main.substring(0, at)
        val rest = main.substring(at + 1)
        val q = rest.indexOf('?')
        val hostPort = if (q >= 0) rest.substring(0, q) else rest
        val query = if (q >= 0) rest.substring(q + 1) else ""
        val (host, port) = splitHostPort(hostPort) ?: return null
        val params = parseQuery(query)

        val security = params["security"] ?: "none"
        val network = params["type"] ?: "tcp"
        val streamSettings = JSONObject().put("network", network)

        when (security) {
            "reality" -> {
                streamSettings.put("security", "reality")
                streamSettings.put(
                    "realitySettings",
                    JSONObject()
                        .put("serverName", params["sni"] ?: params["serverName"] ?: host)
                        .put("fingerprint", params["fp"] ?: "chrome")
                        .put("publicKey", params["pbk"] ?: "")
                        .put("shortId", params["sid"] ?: "")
                        .put("spiderX", params["spx"] ?: "")
                )
            }
            "tls" -> {
                streamSettings.put("security", "tls")
                streamSettings.put(
                    "tlsSettings",
                    JSONObject()
                        .put("serverName", params["sni"] ?: host)
                        .put("fingerprint", params["fp"] ?: "chrome")
                        .put("allowInsecure", params["allowInsecure"] == "1")
                )
            }
        }

        when (network) {
            "ws" -> streamSettings.put(
                "wsSettings",
                JSONObject()
                    .put("path", params["path"] ?: "/")
                    .put("headers", JSONObject().put("Host", params["host"] ?: host))
            )
            "grpc" -> streamSettings.put(
                "grpcSettings",
                JSONObject().put("serviceName", params["serviceName"] ?: params["path"] ?: "")
            )
            "xhttp", "httpupgrade" -> streamSettings.put(
                "xhttpSettings",
                JSONObject().put("path", params["path"] ?: "/")
            )
        }

        return buildFullConfig(
            socksPort,
            JSONObject()
                .put("protocol", "vless")
                .put(
                    "settings",
                    JSONObject().put(
                        "vnext",
                        JSONArray().put(
                            JSONObject()
                                .put("address", host)
                                .put("port", port)
                                .put(
                                    "users",
                                    JSONArray().put(
                                        JSONObject()
                                            .put("id", uuid)
                                            .put("encryption", params["encryption"] ?: "none")
                                            .put("flow", params["flow"] ?: "")
                                    )
                                )
                        )
                    )
                )
                .put("streamSettings", streamSettings)
                .put("tag", "proxy")
        )
    }

    private fun vmessToJson(link: String, socksPort: Int): String? {
        val b64 = link.removePrefix("vmess://")
        val decoded = try {
            String(Base64.decode(b64, Base64.DEFAULT or Base64.URL_SAFE))
        } catch (_: Exception) {
            try {
                String(Base64.decode(b64, Base64.DEFAULT))
            } catch (_: Exception) {
                return null
            }
        }
        val obj = JSONObject(decoded)
        val host = obj.optString("add")
        val port = obj.optInt("port")
        val uuid = obj.optString("id")
        val network = obj.optString("net", "tcp")
        val tls = obj.optString("tls", "")
        val streamSettings = JSONObject().put("network", network)
        if (tls == "tls" || tls == "reality") {
            streamSettings.put("security", tls)
            if (tls == "tls") {
                streamSettings.put(
                    "tlsSettings",
                    JSONObject()
                        .put("serverName", obj.optString("sni", host))
                        .put("fingerprint", obj.optString("fp", "chrome"))
                )
            }
        }
        return buildFullConfig(
            socksPort,
            JSONObject()
                .put("protocol", "vmess")
                .put(
                    "settings",
                    JSONObject().put(
                        "vnext",
                        JSONArray().put(
                            JSONObject()
                                .put("address", host)
                                .put("port", port)
                                .put(
                                    "users",
                                    JSONArray().put(
                                        JSONObject()
                                            .put("id", uuid)
                                            .put("alterId", obj.optInt("aid", 0))
                                            .put("security", obj.optString("scy", "auto"))
                                    )
                                )
                        )
                    )
                )
                .put("streamSettings", streamSettings)
                .put("tag", "proxy")
        )
    }

    private fun trojanToJson(link: String, socksPort: Int): String? {
        val withoutScheme = link.removePrefix("trojan://")
        val hashIdx = withoutScheme.indexOf('#')
        val main = if (hashIdx >= 0) withoutScheme.substring(0, hashIdx) else withoutScheme
        val at = main.indexOf('@')
        if (at < 0) return null
        val password = URLDecoder.decode(main.substring(0, at), "UTF-8")
        val rest = main.substring(at + 1)
        val q = rest.indexOf('?')
        val hostPort = if (q >= 0) rest.substring(0, q) else rest
        val query = if (q >= 0) rest.substring(q + 1) else ""
        val (host, port) = splitHostPort(hostPort) ?: return null
        val params = parseQuery(query)
        val streamSettings = JSONObject()
            .put("network", params["type"] ?: "tcp")
            .put("security", params["security"] ?: "tls")
            .put(
                "tlsSettings",
                JSONObject()
                    .put("serverName", params["sni"] ?: host)
                    .put("fingerprint", params["fp"] ?: "chrome")
            )
        return buildFullConfig(
            socksPort,
            JSONObject()
                .put("protocol", "trojan")
                .put(
                    "settings",
                    JSONObject().put(
                        "servers",
                        JSONArray().put(
                            JSONObject()
                                .put("address", host)
                                .put("port", port)
                                .put("password", password)
                        )
                    )
                )
                .put("streamSettings", streamSettings)
                .put("tag", "proxy")
        )
    }

    /** Split host:port, supporting [IPv6]:port. */
    private fun splitHostPort(hostPort: String): Pair<String, Int>? {
        if (hostPort.startsWith("[")) {
            val end = hostPort.indexOf(']')
            if (end < 0) return null
            val host = hostPort.substring(1, end)
            val rest = hostPort.substring(end + 1)
            if (!rest.startsWith(":")) return null
            val port = rest.removePrefix(":").toIntOrNull() ?: return null
            return host to port
        }
        val colon = hostPort.lastIndexOf(':')
        if (colon < 0) return null
        val host = hostPort.substring(0, colon)
        val port = hostPort.substring(colon + 1).toIntOrNull() ?: return null
        return host to port
    }

    private fun buildFullConfig(socksPort: Int, outbound: JSONObject): String {
        return JSONObject()
            .put("log", JSONObject().put("loglevel", "warning"))
            .put(
                "inbounds",
                JSONArray().put(
                    JSONObject()
                        .put("tag", "socks-in")
                        .put("port", socksPort)
                        .put("listen", "127.0.0.1")
                        .put("protocol", "socks")
                        .put("settings", JSONObject().put("udp", true))
                )
            )
            .put("outbounds", JSONArray().put(outbound).put(
                JSONObject().put("protocol", "freedom").put("tag", "direct")
            ))
            .toString()
    }

    private fun parseQuery(query: String): Map<String, String> {
        if (query.isEmpty()) return emptyMap()
        return query.split('&').mapNotNull { part ->
            val eq = part.indexOf('=')
            if (eq < 0) return@mapNotNull null
            val k = URLDecoder.decode(part.substring(0, eq), "UTF-8")
            val v = URLDecoder.decode(part.substring(eq + 1), "UTF-8")
            k to v
        }.toMap()
    }
}
