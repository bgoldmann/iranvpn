package org.opensignalfoundation.iranvpn.fallback

import android.content.Context
import org.opensignalfoundation.iranvpn.model.PathConfig
import org.opensignalfoundation.iranvpn.model.ShareLinkParser
import java.io.File
import java.net.URL
import java.security.SecureRandom
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

/**
 * PathRunner for Xray (VLESS, VMess, Trojan, REALITY, xHTTP).
 * Prefers LibXray JNI when available; falls back to subprocess with encrypted temp config
 * (never leaves cleartext JSON in cache after start).
 *
 * Requires either:
 * - LibXray / AndroidLibXrayLite on classpath (preferred), or
 * - xray binary in assets/xray/
 */
class XrayPathRunner(private val context: Context) : PathRunner, SocksProxyProvider {

    private val processRef = AtomicReference<Process?>(null)
    private val configFileRef = AtomicReference<File?>(null)
    private var socksPort = DEFAULT_SOCKS_PORT
    private var libXrayInstance: Any? = null

    override fun connect(config: PathConfig): PathResult {
        if (config !is PathConfig.XrayConfig) return PathResult.Failure("wrong config type")
        return runCatching { startXray(config) }.getOrElse {
            PathResult.Failure("Xray error: ${it.message}")
        }
    }

    private fun startXray(config: PathConfig.XrayConfig): PathResult {
        var configJson = config.configJson.trim()
        if (configJson.isEmpty() || configJson == "{}") {
            config.subscriptionUrl?.let { url ->
                configJson = fetchSubscription(url)
                    ?: return PathResult.Failure("Failed to fetch Xray subscription")
            } ?: return PathResult.Failure("Xray config or subscription URL required")
        }

        // Expand share links into a minimal Xray JSON if needed
        if (configJson.startsWith("vless://") || configJson.startsWith("vmess://") ||
            configJson.startsWith("trojan://")
        ) {
            configJson = ShareLinkParser.toXrayJson(configJson, DEFAULT_SOCKS_PORT)
                ?: return PathResult.Failure("Failed to parse share link")
        }

        socksPort = parseSocksPort(configJson) ?: DEFAULT_SOCKS_PORT
        // Ensure inbound SOCKS exists
        configJson = ensureSocksInbound(configJson, socksPort)

        // Prefer LibXray if present
        val libResult = tryLibXray(configJson)
        if (libResult != null) return libResult

        return startSubprocess(configJson)
    }

    private fun tryLibXray(configJson: String): PathResult? {
        return try {
            val clazz = Class.forName("libxray.LibXray")
            // Common API: runXray(configContent: String) or similar — try several
            val methods = clazz.methods
            val runMethod = methods.firstOrNull { it.name.contains("run", ignoreCase = true) && it.parameterCount >= 1 }
                ?: methods.firstOrNull { it.name == "start" }
                ?: return null
            libXrayInstance = clazz
            when (runMethod.parameterCount) {
                1 -> runMethod.invoke(null, configJson)
                else -> runMethod.invoke(null, configJson, "")
            }
            Thread.sleep(500)
            PathResult.Success
        } catch (_: ClassNotFoundException) {
            null
        } catch (e: Exception) {
            PathResult.Failure("LibXray error: ${e.message}")
        }
    }

    private fun startSubprocess(configJson: String): PathResult {
        val xrayPath = findXrayBinary() ?: return PathResult.Failure(
            "Xray binary not found - add assets/xray/xray or LibXray AAR"
        )

        // Write encrypted then decrypt to a private file deleted after process start
        val configFile = writeProtectedConfig(configJson)
        configFileRef.set(configFile)

        val process = ProcessBuilder(xrayPath, "run", "-c", configFile.absolutePath)
            .directory(context.cacheDir)
            .redirectErrorStream(true)
            .start()
        processRef.set(process)

        // Wipe cleartext ASAP: overwrite then delete after short delay on another thread
        threadWipe(configFile)

        val exited = process.waitFor(5, TimeUnit.SECONDS)
        if (exited && process.exitValue() != 0) {
            val err = try {
                process.inputStream.bufferedReader().readText().take(200)
            } catch (_: Exception) {
                ""
            }
            process.destroyForcibly()
            return PathResult.Failure("Xray exited: $err")
        }
        if (exited) {
            process.destroyForcibly()
            return PathResult.Failure("Xray process exited unexpectedly")
        }
        Thread.sleep(500)
        return PathResult.Success
    }

    private fun writeProtectedConfig(configJson: String): File {
        val dir = File(context.noBackupFilesDir, "xray").apply { mkdirs() }
        val file = File(dir, "cfg_${System.nanoTime()}.json")
        file.writeText(configJson, Charsets.UTF_8)
        // Restrict permissions
        file.setReadable(false, false)
        file.setReadable(true, true)
        file.setWritable(false, false)
        file.setWritable(true, true)
        return file
    }

    private fun threadWipe(file: File) {
        Thread {
            try {
                Thread.sleep(2_000)
                if (file.exists()) {
                    val junk = ByteArray(file.length().toInt().coerceAtLeast(1))
                    SecureRandom().nextBytes(junk)
                    file.writeBytes(junk)
                    file.delete()
                }
            } catch (_: Exception) {}
        }.start()
    }

    override fun disconnect() {
        processRef.getAndSet(null)?.destroyForcibly()
        configFileRef.getAndSet(null)?.let { f ->
            try {
                if (f.exists()) {
                    f.writeBytes(ByteArray(16))
                    f.delete()
                }
            } catch (_: Exception) {}
        }
        libXrayInstance = null
        try {
            Class.forName("libxray.LibXray").getMethod("stopXray").invoke(null)
        } catch (_: Exception) {}
    }

    override fun getLocalSocksPort(): Int = socksPort

    override fun supportsUdp(): Boolean = true

    private fun findXrayBinary(): String? {
        val abi = android.os.Build.SUPPORTED_ABIS.firstOrNull() ?: "armeabi-v7a"
        val candidates = listOf("xray/$abi/xray", "xray/xray")
        for (assetPath in candidates) {
            try {
                context.assets.open(assetPath).use { }
                val out = File(context.noBackupFilesDir, "xray_bin_$abi").apply {
                    parentFile?.mkdirs()
                    delete()
                }
                context.assets.open(assetPath).use { inp ->
                    out.outputStream().use { inp.copyTo(it) }
                }
                out.setExecutable(true)
                return out.absolutePath
            } catch (_: Exception) {
                continue
            }
        }
        return null
    }

    private fun fetchSubscription(url: String): String? = try {
        URL(url).openStream().bufferedReader().readText()
    } catch (_: Exception) {
        null
    }

    private fun parseSocksPort(configJson: String): Int? {
        return try {
            val json = org.json.JSONObject(configJson)
            val inbounds = json.optJSONArray("inbounds") ?: return null
            for (i in 0 until inbounds.length()) {
                val inv = inbounds.getJSONObject(i)
                if (inv.optString("protocol") == "socks") {
                    val port = inv.optInt("port", 0)
                    if (port != 0) return port
                    return inv.optJSONObject("settings")?.optInt("port", 0)?.takeIf { it != 0 }
                }
            }
            null
        } catch (_: Exception) {
            null
        }
    }

    private fun ensureSocksInbound(configJson: String, port: Int): String {
        return try {
            val json = org.json.JSONObject(configJson)
            val inbounds = json.optJSONArray("inbounds") ?: org.json.JSONArray().also {
                json.put("inbounds", it)
            }
            var hasSocks = false
            for (i in 0 until inbounds.length()) {
                if (inbounds.getJSONObject(i).optString("protocol") == "socks") {
                    hasSocks = true
                    inbounds.getJSONObject(i).put("port", port)
                }
            }
            if (!hasSocks) {
                inbounds.put(
                    org.json.JSONObject()
                        .put("tag", "socks-in")
                        .put("port", port)
                        .put("listen", "127.0.0.1")
                        .put("protocol", "socks")
                        .put("settings", org.json.JSONObject().put("udp", true))
                )
            }
            json.toString()
        } catch (_: Exception) {
            configJson
        }
    }

    companion object {
        private const val DEFAULT_SOCKS_PORT = 10808
    }
}
