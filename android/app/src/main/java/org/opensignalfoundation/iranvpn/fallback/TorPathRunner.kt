package org.opensignalfoundation.iranvpn.fallback

import android.content.Context
import android.content.Intent
import android.net.Uri
import org.opensignalfoundation.iranvpn.model.PathConfig
import java.io.File
import java.net.InetSocketAddress
import java.net.Socket
import java.util.concurrent.atomic.AtomicReference

/**
 * Tor path: prefer local Orbot SOCKS (9050), else bundled `tor` binary with optional bridges.
 * Snowflake / WebTunnel: put bridge lines in TorConfig.bridges.
 */
class TorPathRunner(private val context: Context) : PathRunner, SocksProxyProvider {
    private val processRef = AtomicReference<Process?>(null)
    private var socksPort: Int = 9050

    override fun connect(config: PathConfig): PathResult {
        if (config !is PathConfig.TorConfig) return PathResult.Failure("wrong config type")
        socksPort = config.socksPort ?: 9050

        if (portOpen(socksPort)) {
            return PathResult.Success
        }

        val torBin = AssetBinary.findOrExtract(
            context,
            listOf("tor/\$ABI/tor", "tor/tor"),
            "tor",
        )
        if (torBin == null) {
            return PathResult.Failure(
                "Tor SOCKS not found on :$socksPort and no assets/tor binary. " +
                    "Install Orbot or add a Tor binary.",
            )
        }

        val dataDir = File(context.noBackupFilesDir, "tor-data").apply { mkdirs() }
        val torrc = File(context.noBackupFilesDir, "torrc").apply {
            val bridges = config.bridges.filter { it.isNotBlank() }
            writeText(
                buildString {
                    appendLine("DataDirectory ${dataDir.absolutePath}")
                    appendLine("SocksPort 127.0.0.1:$socksPort")
                    appendLine("AvoidDiskWrites 1")
                    if (bridges.isNotEmpty()) {
                        appendLine("UseBridges 1")
                        for (b in bridges) appendLine("Bridge $b")
                    }
                },
            )
        }

        return try {
            val p = ProcessBuilder(torBin, "-f", torrc.absolutePath)
                .directory(context.cacheDir)
                .redirectErrorStream(true)
                .start()
            processRef.set(p)
            // Tor bootstrap can take a while
            for (_i in 0 until 40) {
                if (portOpen(socksPort)) return PathResult.Success
                if (!p.isAlive) {
                    val err = p.inputStream.bufferedReader().readText().take(240)
                    return PathResult.Failure("tor exited: $err")
                }
                Thread.sleep(500)
            }
            PathResult.Failure("Tor SOCKS not ready on $socksPort")
        } catch (e: Exception) {
            PathResult.Failure("tor: ${e.message}")
        }
    }

    override fun disconnect() {
        processRef.getAndSet(null)?.destroyForcibly()
    }

    override fun getLocalSocksPort(): Int = socksPort

    override fun supportsUdp(): Boolean = false

    companion object {
        fun isOrbotInstalled(context: Context): Boolean {
            return try {
                context.packageManager.getPackageInfo("org.torproject.android", 0)
                true
            } catch (_: Exception) {
                false
            }
        }

        fun openOrbotPlayStore(context: Context) {
            val intent = Intent(
                Intent.ACTION_VIEW,
                Uri.parse("market://details?id=org.torproject.android"),
            ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            try {
                context.startActivity(intent)
            } catch (_: Exception) {
                context.startActivity(
                    Intent(
                        Intent.ACTION_VIEW,
                        Uri.parse("https://play.google.com/store/apps/details?id=org.torproject.android"),
                    ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                )
            }
        }

        private fun portOpen(port: Int): Boolean {
            return try {
                Socket().use { s ->
                    s.connect(InetSocketAddress("127.0.0.1", port), 400)
                    true
                }
            } catch (_: Exception) {
                false
            }
        }
    }
}
