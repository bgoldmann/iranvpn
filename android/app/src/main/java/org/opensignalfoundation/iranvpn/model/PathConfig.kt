package org.opensignalfoundation.iranvpn.model

import org.json.JSONArray
import org.json.JSONObject

/**
 * Kotlin mirror of core PathConfig. Parsed from JSON.
 */
sealed class PathConfig {
    abstract fun kind(): PathKind

    data class PsiphonConfig(
        val serverListUrl: String?,
        val inproxyClientPersonalCompartmentId: String? = null,
    ) : PathConfig() {
        override fun kind() = PathKind.PSIPHON
    }

    data class ConduitConfig(
        val discoveryUrl: String?,
        val personalCompartmentId: String? = null,
    ) : PathConfig() {
        override fun kind() = PathKind.CONDUIT
    }

    data class XrayConfig(val configJson: String, val subscriptionUrl: String?) : PathConfig() {
        override fun kind() = PathKind.XRAY
    }

    data class SingBoxConfig(val configJson: String, val subscriptionUrl: String?) : PathConfig() {
        override fun kind() = PathKind.SINGBOX
    }

    data class TorConfig(val bridges: List<String> = emptyList(), val socksPort: Int? = null) : PathConfig() {
        override fun kind() = PathKind.TOR
    }

    data class OutlineConfig(val accessKey: String) : PathConfig() {
        override fun kind() = PathKind.OUTLINE
    }

    data class AmneziaWgConfig(val config: String) : PathConfig() {
        override fun kind() = PathKind.AMNEZIAWG
    }

    data class RostamConfig(val wireguardConfig: String) : PathConfig() {
        override fun kind() = PathKind.ROSTAM
    }

    companion object {
        fun fromJson(obj: JSONObject): PathConfig {
            return when (obj.optString("type", "")) {
                "psiphon" -> PsiphonConfig(
                    serverListUrl = obj.optString("server_list_url").takeIf { it.isNotEmpty() },
                    inproxyClientPersonalCompartmentId = obj
                        .optString("inproxy_client_personal_compartment_id")
                        .takeIf { it.isNotEmpty() },
                )
                "conduit" -> ConduitConfig(
                    discoveryUrl = obj.optString("discovery_url").takeIf { it.isNotEmpty() },
                    personalCompartmentId = obj
                        .optString("personal_compartment_id")
                        .takeIf { it.isNotEmpty() },
                )
                "xray" -> XrayConfig(
                    configJson = obj.optString("config_json", "{}"),
                    subscriptionUrl = obj.optString("subscription_url").takeIf { it.isNotEmpty() },
                )
                "singbox", "sing_box" -> SingBoxConfig(
                    configJson = obj.optString("config_json", "{}"),
                    subscriptionUrl = obj.optString("subscription_url").takeIf { it.isNotEmpty() },
                )
                "tor" -> {
                    val bridges = mutableListOf<String>()
                    val arr = obj.optJSONArray("bridges")
                    if (arr != null) {
                        for (i in 0 until arr.length()) {
                            arr.optString(i).takeIf { it.isNotEmpty() }?.let { bridges.add(it) }
                        }
                    }
                    TorConfig(
                        bridges = bridges,
                        socksPort = obj.optInt("socks_port", 0).takeIf { it > 0 },
                    )
                }
                "outline" -> OutlineConfig(accessKey = obj.getString("access_key"))
                "amneziawg", "amnezia_wg" -> AmneziaWgConfig(config = obj.getString("config"))
                "rostam" -> RostamConfig(wireguardConfig = obj.getString("wireguard_config"))
                else -> throw IllegalArgumentException("unknown path type: ${obj.optString("type")}")
            }
        }

        fun toJson(p: PathConfig): JSONObject = when (p) {
            is PsiphonConfig -> JSONObject()
                .put("type", "psiphon")
                .put("server_list_url", p.serverListUrl ?: JSONObject.NULL)
                .put(
                    "inproxy_client_personal_compartment_id",
                    p.inproxyClientPersonalCompartmentId ?: JSONObject.NULL,
                )
            is ConduitConfig -> JSONObject()
                .put("type", "conduit")
                .put("discovery_url", p.discoveryUrl ?: JSONObject.NULL)
                .put("personal_compartment_id", p.personalCompartmentId ?: JSONObject.NULL)
            is XrayConfig -> JSONObject()
                .put("type", "xray")
                .put("config_json", p.configJson)
                .put("subscription_url", p.subscriptionUrl ?: JSONObject.NULL)
            is SingBoxConfig -> JSONObject()
                .put("type", "singbox")
                .put("config_json", p.configJson)
                .put("subscription_url", p.subscriptionUrl ?: JSONObject.NULL)
            is TorConfig -> JSONObject()
                .put("type", "tor")
                .put("bridges", JSONArray(p.bridges))
                .put("socks_port", p.socksPort ?: JSONObject.NULL)
            is OutlineConfig -> JSONObject()
                .put("type", "outline")
                .put("access_key", p.accessKey)
            is AmneziaWgConfig -> JSONObject()
                .put("type", "amneziawg")
                .put("config", p.config)
            is RostamConfig -> JSONObject()
                .put("type", "rostam")
                .put("wireguard_config", p.wireguardConfig)
        }
    }
}
