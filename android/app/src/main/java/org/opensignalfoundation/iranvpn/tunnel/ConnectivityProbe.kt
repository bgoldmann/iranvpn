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

    /**
     * Fetch [url] via SOCKS5 at 127.0.0.1:[socksPort] and require [token] in the body.
     * Returns Result.success on match; failure otherwise.
     */
    fun probeThroughSocks(
        socksPort: Int,
        url: String = DEFAULT_PROBE_URL,
        token: String = DEFAULT_TOKEN_SUBSTRING,
    ): Result<Unit> {
        if (socksPort <= 0) {
            return Result.failure(IllegalStateException("no SOCKS port"))
        }
        return runCatching {
            val proxy = Proxy(Proxy.Type.SOCKS, InetSocketAddress("127.0.0.1", socksPort))
            val conn = (URL(url).openConnection(proxy) as HttpsURLConnection).apply {
                connectTimeout = TIMEOUT_MS
                readTimeout = TIMEOUT_MS
                requestMethod = "GET"
                instanceFollowRedirects = true
                setRequestProperty("User-Agent", "IranVPN/1.0")
            }
            try {
                conn.connect()
                if (conn.responseCode !in 200..299) {
                    error("probe HTTP ${conn.responseCode}")
                }
                val body = BufferedReader(InputStreamReader(conn.inputStream)).use { it.readText() }
                if (!body.contains(token)) {
                    error("probe token missing")
                }
            } finally {
                conn.disconnect()
            }
        }
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
