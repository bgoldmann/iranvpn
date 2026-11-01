package org.opensignalfoundation.iranvpn

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import org.opensignalfoundation.iranvpn.model.ConfigSource
import org.opensignalfoundation.iranvpn.model.PathConfig
import org.opensignalfoundation.iranvpn.model.ServerList
import java.io.File
import java.net.InetSocketAddress
import java.net.Proxy
import java.net.URL
import javax.net.ssl.HttpsURLConnection
import kotlin.concurrent.thread

/**
 * Bootstrap: last-good → embedded. No clearnet fetch before Connect.
 * After SOCKS is up, [refreshInBackground] pulls the published list and keeps
 * any locally imported paths the publish does not already contain.
 */
object ConfigFetcher {
    private const val LAST_GOOD_FILE = "last_good_server_list.json"

    private val defaultSources = listOf(
        // Same order as core/src/bootstrap.rs and dist-config/server-list.json.
        ConfigSource(
            url = "https://iranvpn-config.goldmannllc.com/server-list.json",
            label = "Mirror (Cloudflare Worker)",
        ),
        ConfigSource(
            url = "https://raw.githubusercontent.com/bgoldmann/iranvpn/main/dist-config/server-list.json",
            label = "Primary (GitHub)",
        ),
        ConfigSource(
            url = "https://cdn.jsdelivr.net/gh/bgoldmann/iranvpn@main/dist-config/server-list.json",
            label = "Mirror (jsDelivr)",
        ),
    )

    fun defaultSources(): List<ConfigSource> = defaultSources

    fun embeddedBootstrap(): ServerList {
        return ServerList.fromJson(
            """{"paths":[{"type":"psiphon","server_list_url":null}],"sources":[]}"""
        )
    }

    fun fetch(context: Context? = null): Result<ServerList> {
        val list = context?.let { loadLastGood(it) }?.takeIf { it.paths.isNotEmpty() }
            ?: embeddedBootstrap()
        return Result.success(list)
    }

    /**
     * Fetch the published list through the local SOCKS port and save a merge.
     * Published paths win. A Psiphon personal compartment and any imported path
     * type the publish does not include are kept.
     */
    fun refreshInBackground(context: Context, socksPort: Int) {
        if (socksPort <= 0) return
        val appContext = context.applicationContext
        thread(name = "config-refresh", isDaemon = true) {
            val fresh = refreshViaSocks(socksPort) ?: return@thread
            val local = loadLastGood(appContext)
            saveLastGood(appContext, merge(local, fresh))
        }
    }

    fun merge(local: ServerList?, fresh: ServerList): ServerList {
        val compartment = local?.paths
            ?.filterIsInstance<PathConfig.PsiphonConfig>()
            ?.firstOrNull()
            ?.inproxyClientPersonalCompartmentId
        val freshKinds = fresh.paths.map { it.kind() }.toSet()
        val published = fresh.paths.map { path ->
            if (
                path is PathConfig.PsiphonConfig &&
                path.inproxyClientPersonalCompartmentId.isNullOrBlank() &&
                !compartment.isNullOrBlank()
            ) {
                path.copy(inproxyClientPersonalCompartmentId = compartment)
            } else {
                path
            }
        }
        val extras = local?.paths.orEmpty().filter { path ->
            path !is PathConfig.PsiphonConfig && path.kind() !in freshKinds
        }
        val sources = fresh.sources.ifEmpty { local?.sources.orEmpty() }
        return ServerList(paths = published + extras, sources = sources)
    }

    private fun refreshViaSocks(socksPort: Int): ServerList? {
        val proxy = Proxy(Proxy.Type.SOCKS, InetSocketAddress("127.0.0.1", socksPort))
        for (source in defaultSources) {
            try {
                val list = ServerList.fromJson(fetchUrl(source.url, proxy))
                if (list.paths.isNotEmpty()) return list
            } catch (_: Exception) {
                continue
            }
        }
        return null
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
                PathConfig.toJson(p)
            )
        }
        obj.put("paths", paths)
        val sources = JSONArray()
        for (s in list.sources) {
            val o = JSONObject().put("url", s.url)
            if (!s.label.isNullOrEmpty()) o.put("label", s.label)
            sources.put(o)
        }
        obj.put("sources", sources)
        return obj.toString()
    }

    private fun fetchUrl(url: String, proxy: Proxy): String {
        val conn = URL(url).openConnection(proxy) as HttpsURLConnection
        conn.connectTimeout = 10_000
        conn.readTimeout = 10_000
        conn.requestMethod = "GET"
        conn.instanceFollowRedirects = true
        conn.setRequestProperty("User-Agent", "IranVPN/1.0")
        conn.setRequestProperty("Accept-Encoding", "identity")
        conn.connect()
        try {
            if (conn.responseCode != 200) throw RuntimeException("HTTP ${conn.responseCode}")
            return conn.inputStream.bufferedReader().use { it.readText() }
        } finally {
            conn.disconnect()
        }
    }
}
