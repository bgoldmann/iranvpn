package org.opensignalfoundation.iranvpn

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import org.opensignalfoundation.iranvpn.model.ConfigSource
import org.opensignalfoundation.iranvpn.model.PathConfig
import org.opensignalfoundation.iranvpn.model.ServerList
import java.io.File
import java.net.URL
import javax.net.ssl.HttpsURLConnection

/**
 * Bootstrap: last-good → embedded → optional network fetch.
 */
object ConfigFetcher {
    private const val LAST_GOOD_FILE = "last_good_server_list.json"

    private val defaultSources = listOf(
        ConfigSource(
            url = "https://raw.githubusercontent.com/opensignalfoundation/iran-vpn/main/dist-config/server-list.json",
            label = "Primary"
        ),
        ConfigSource(
            url = "https://cdn.jsdelivr.net/gh/opensignalfoundation/iran-vpn@main/dist-config/server-list.json",
            label = "Mirror"
        ),
    )

    fun defaultSources(): List<ConfigSource> = defaultSources

    fun embeddedBootstrap(): ServerList {
        return ServerList.fromJson(
            """{"paths":[{"type":"psiphon","server_list_url":null}],"sources":[]}"""
        )
    }

    fun fetch(
        sources: List<ConfigSource> = defaultSources,
        context: Context? = null,
    ): Result<ServerList> {
        return runCatching {
            context?.let { loadLastGood(it) }?.takeIf { it.paths.isNotEmpty() }?.let {
                return@runCatching it
            }
            if (Native.isAvailable()) {
                val arr = JSONArray()
                sources.forEach { s ->
                    arr.put(JSONObject().apply {
                        put("url", s.url)
                        put("label", s.label)
                    })
                }
                ServerList.fromJson(Native.fetchServerList(arr.toString()))
            } else {
                fetchViaHttp(sources)
            }
        }.recoverCatching {
            context?.let { loadLastGood(it) } ?: embeddedBootstrap()
        }
    }

    fun saveLastGood(context: Context, list: ServerList) {
        try {
            val file = File(context.noBackupFilesDir, LAST_GOOD_FILE)
            file.writeText(serialize(list), Charsets.UTF_8)
        } catch (_: Exception) {}
    }

    fun loadLastGood(context: Context): ServerList? {
        return try {
            val file = File(context.noBackupFilesDir, LAST_GOOD_FILE)
            if (!file.exists()) return null
            ServerList.fromJson(file.readText()).takeIf { it.paths.isNotEmpty() }
        } catch (_: Exception) {
            null
        }
    }

    private fun serialize(list: ServerList): String {
        val obj = JSONObject()
        val paths = JSONArray()
        for (p in list.paths) {
            paths.put(
                when (p) {
                    is PathConfig.PsiphonConfig ->
                        JSONObject().put("type", "psiphon").put("server_list_url", p.serverListUrl ?: JSONObject.NULL)
                    is PathConfig.ConduitConfig ->
                        JSONObject().put("type", "conduit").put("discovery_url", p.discoveryUrl ?: JSONObject.NULL)
                    is PathConfig.XrayConfig ->
                        JSONObject().put("type", "xray")
                            .put("config_json", p.configJson)
                            .put("subscription_url", p.subscriptionUrl ?: JSONObject.NULL)
                    is PathConfig.RostamConfig ->
                        JSONObject().put("type", "rostam").put("wireguard_config", p.wireguardConfig)
                }
            )
        }
        obj.put("paths", paths)
        obj.put("sources", JSONArray())
        return obj.toString()
    }

    private fun fetchViaHttp(sources: List<ConfigSource>): ServerList {
        for (source in sources) {
            try {
                return ServerList.fromJson(fetchUrl(source.url))
            } catch (_: Exception) {
                continue
            }
        }
        throw RuntimeException("all config sources failed")
    }

    private fun fetchUrl(url: String): String {
        val conn = URL(url).openConnection() as HttpsURLConnection
        conn.connectTimeout = 10_000
        conn.readTimeout = 10_000
        conn.requestMethod = "GET"
        conn.connect()
        if (conn.responseCode != 200) throw RuntimeException("HTTP ${conn.responseCode}")
        return conn.inputStream.bufferedReader().use { it.readText() }
    }
}
