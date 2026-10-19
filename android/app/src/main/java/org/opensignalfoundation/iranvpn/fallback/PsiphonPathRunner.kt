package org.opensignalfoundation.iranvpn.fallback

import android.content.Context
import android.net.VpnService
import org.opensignalfoundation.iranvpn.VpnTunnelService
import org.opensignalfoundation.iranvpn.model.PathConfig
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

/**
 * PathRunner for Psiphon (includes Conduit P2P automatically).
 * HostService must implement loadLibrary("gojni") and bindToDevice(long)
 * so native code loads and bridge sockets bypass the TUN.
 */
class PsiphonPathRunner(private val context: Context) : PathRunner, SocksProxyProvider {

    private var tunnelInstance: Any? = null
    private val socksPort = AtomicInteger(0)

    override fun connect(config: PathConfig): PathResult {
        if (config !is PathConfig.PsiphonConfig) return PathResult.Failure("wrong config type")
        return try {
            connectViaPsiphon()
        } catch (e: ClassNotFoundException) {
            PathResult.Failure("Psiphon SDK not on classpath - add ca.psiphon:psiphontunnel dependency")
        } catch (e: UnsatisfiedLinkError) {
            PathResult.Failure("Psiphon native library failed to load: ${e.message}")
        } catch (e: Exception) {
            PathResult.Failure("Psiphon error: ${e.message}")
        }
    }

    private fun connectViaPsiphon(): PathResult {
        val latch = CountDownLatch(1)
        val errorHolder = arrayOfNulls<String>(1)
        socksPort.set(0)

        val tunnelClass = Class.forName("ca.psiphon.PsiphonTunnel")
        val hostServiceClass = Class.forName("ca.psiphon.PsiphonTunnel\$HostService")

        val vpnService = context as? VpnService

        val hostService = java.lang.reflect.Proxy.newProxyInstance(
            hostServiceClass.classLoader,
            arrayOf(hostServiceClass)
        ) { _, method, args ->
            when (method.name) {
                "getContext" -> context.applicationContext
                "getPsiphonConfig" -> psiphonConfigJson()
                "loadLibrary" -> {
                    // Required: Psiphon loads gojni through the host
                    val name = args?.getOrNull(0)?.toString() ?: "gojni"
                    System.loadLibrary(name)
                    null
                }
                "onConnected" -> {
                    refreshSocksPort()
                    latch.countDown()
                    null
                }
                "onExiting" -> {
                    socksPort.set(0)
                    null
                }
                "onListeningSocksProxyPort" -> {
                    (args?.getOrNull(0) as? Number)?.toInt()?.let { socksPort.set(it) }
                    null
                }
                "onUpstreamProxyError" -> {
                    errorHolder[0] = args?.getOrNull(0)?.toString()
                    null
                }
                // Current Psiphon API: bindToDevice(long fileDescriptor)
                "bindToDevice" -> {
                    val fdLong = when (val a = args?.getOrNull(0)) {
                        is Long -> a
                        is Int -> a.toLong()
                        is Number -> a.toLong()
                        else -> return@newProxyInstance false
                    }
                    protectFd(vpnService, fdLong)
                }
                // Legacy name kept for older SDKs
                "protectSocket" -> {
                    val fd = when (val a = args?.getOrNull(0)) {
                        is Int -> a
                        is Long -> a.toInt()
                        is Number -> a.toInt()
                        else -> return@newProxyInstance false
                    }
                    vpnService?.protect(fd) ?: false
                }
                else -> when (method.returnType.name) {
                    "void" -> null
                    "boolean" -> false
                    "int" -> 0
                    "long" -> 0L
                    else -> null
                }
            }
        }

        val newTunnel = tunnelClass.getMethod("newPsiphonTunnel", hostServiceClass)
            .invoke(null, hostService)
        tunnelInstance = newTunnel
        newTunnel?.javaClass?.getMethod("setVpnMode", Boolean::class.javaPrimitiveType)
            ?.invoke(newTunnel, false)
        newTunnel?.javaClass?.getMethod("startTunneling", String::class.java)
            ?.invoke(newTunnel, "")

        val ok = latch.await(90, TimeUnit.SECONDS)
        if (!ok) {
            disconnect()
            return PathResult.Failure(errorHolder[0] ?: "Psiphon connection timeout")
        }
        refreshSocksPort()
        if (socksPort.get() <= 0) {
            disconnect()
            return PathResult.Failure("Psiphon SOCKS port unavailable")
        }
        return PathResult.Success
    }

    private fun protectFd(vpn: VpnService?, fdLong: Long): Boolean {
        if (vpn == null) return false
        val fdInt = fdLong.toInt()
        return try {
            if (vpn is VpnTunnelService) vpn.protectSocket(fdInt) else vpn.protect(fdInt)
        } catch (_: Exception) {
            false
        }
    }

    private fun refreshSocksPort() {
        try {
            val port = tunnelInstance?.javaClass
                ?.getMethod("getLocalSocksProxyPort")
                ?.invoke(tunnelInstance) as? Int ?: 0
            if (port > 0) socksPort.set(port)
        } catch (_: Exception) {}
    }

    private fun psiphonConfigJson(): String {
        return """
            {
              "EmitDiagnosticNotices": false,
              "EstablishTunnelTimeoutSeconds": 60,
              "LocalSocksProxyPort": 0,
              "LocalHttpProxyPort": 0,
              "DisableLocalSocksAuth": true
            }
        """.trimIndent()
    }

    override fun disconnect() {
        try {
            tunnelInstance?.javaClass?.getMethod("stop")?.invoke(tunnelInstance)
        } catch (_: Exception) {
            try {
                tunnelInstance?.javaClass?.getMethod("stopTunneling")?.invoke(tunnelInstance)
            } catch (_: Exception) {}
        }
        tunnelInstance = null
        socksPort.set(0)
    }

    override fun getLocalSocksPort(): Int {
        val cached = socksPort.get()
        if (cached > 0) return cached
        refreshSocksPort()
        return socksPort.get()
    }

    override fun supportsUdp(): Boolean = false
}
