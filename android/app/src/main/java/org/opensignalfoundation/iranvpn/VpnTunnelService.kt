package org.opensignalfoundation.iranvpn

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import org.opensignalfoundation.iranvpn.fallback.AmneziaWgPathRunner
import org.opensignalfoundation.iranvpn.fallback.FallbackOrchestrator
import org.opensignalfoundation.iranvpn.fallback.OutlinePathRunner
import org.opensignalfoundation.iranvpn.fallback.PathRunner
import org.opensignalfoundation.iranvpn.fallback.PsiphonPathRunner
import org.opensignalfoundation.iranvpn.fallback.SingBoxPathRunner
import org.opensignalfoundation.iranvpn.fallback.SocksProxyProvider
import org.opensignalfoundation.iranvpn.fallback.TorPathRunner
import org.opensignalfoundation.iranvpn.fallback.XrayPathRunner
import org.opensignalfoundation.iranvpn.metrics.LocalFailureLog
import org.opensignalfoundation.iranvpn.model.PathKind
import org.opensignalfoundation.iranvpn.tunnel.ConnectivityProbe
import org.opensignalfoundation.iranvpn.tunnel.PacketForwarder
import kotlin.concurrent.thread

/**
 * VPN tunnel service: race paths → probe → TUN with kill switch.
 * addDisallowedApplication prevents TUN loop; DNS is TUN-local.
 */
class VpnTunnelService : VpnService() {

    private var tunnelFd: ParcelFileDescriptor? = null
    private var running = false
    private var activeRunner: PathRunner? = null
    private var healthThread: Thread? = null
    private var reconnecting = false

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_CONNECT -> connect()
            ACTION_DISCONNECT -> disconnect(stop = true)
            ACTION_RECONNECT -> {
                if (!reconnecting) {
                    softReconnect()
                }
            }
        }
        return START_STICKY
    }

    fun protectSocket(fd: Int): Boolean = protect(fd)

    private fun connect() {
        if (running) return
        isConnecting = true
        isConnected = false
        startAsForeground("Connecting…")
        running = true

        thread(name = "vpn-connect") {
            runConnectAttempt(reuseTun = false)
        }
    }

    /**
     * Reconnect without tearing down the TUN interface first — keeps a blackhole
     * kill switch instead of a cleartext window while the next path races.
     */
    private fun softReconnect() {
        reconnecting = true
        isConnecting = true
        isConnected = false
        healthThread?.interrupt()
        healthThread = null
        PacketForwarder.stop()
        activeRunner?.disconnect()
        activeRunner = null
        activePathName = null
        runOnMain { updateNotification("Reconnecting…") }
        running = true
        thread(name = "vpn-reconnect") {
            try {
                runConnectAttempt(reuseTun = tunnelFd != null)
            } finally {
                reconnecting = false
            }
        }
    }

    private fun runConnectAttempt(reuseTun: Boolean) {
        var connectedRunners: Map<PathKind, PathRunner>? = null
        var fetchedList: org.opensignalfoundation.iranvpn.model.ServerList? = null
        val result = runBlocking {
            withContext(Dispatchers.IO) {
                val serverList = ConfigFetcher.fetch(context = this@VpnTunnelService).getOrElse {
                    ConfigFetcher.loadLastGood(this@VpnTunnelService)
                        ?: return@withContext Result.failure(it)
                }
                fetchedList = serverList
                val pathRunners = buildMap<PathKind, PathRunner> {
                    put(PathKind.PSIPHON, PsiphonPathRunner(this@VpnTunnelService))
                    if (XrayPathRunner.isAvailable(this@VpnTunnelService)) {
                        put(PathKind.XRAY, XrayPathRunner(this@VpnTunnelService))
                    }
                    if (SingBoxPathRunner.isAvailable(this@VpnTunnelService)) {
                        put(PathKind.SINGBOX, SingBoxPathRunner(this@VpnTunnelService))
                        put(PathKind.OUTLINE, OutlinePathRunner(this@VpnTunnelService))
                    }
                    put(PathKind.TOR, TorPathRunner(this@VpnTunnelService))
                    put(PathKind.AMNEZIAWG, AmneziaWgPathRunner(this@VpnTunnelService))
                }
                connectedRunners = pathRunners
                FallbackOrchestrator(serverList, pathRunners).run()
            }
        }

        result.fold(
            onSuccess = { pathKind ->
                // User cancelled / disconnected while the race was still running.
                if (!running) {
                    connectedRunners?.values?.forEach { it.disconnect() }
                    return@fold
                }
                val runner = connectedRunners?.get(pathKind)
                activeRunner = runner
                val socks = runner as? SocksProxyProvider
                val socksPort = ConnectivityProbe.awaitSocks(
                    { socks?.getLocalSocksPort() ?: 0 },
                    timeoutMs = 20_000,
                )
                if (!running) {
                    runner?.disconnect()
                    return@fold
                }
                if (socksPort <= 0) {
                    LocalFailureLog.record(this@VpnTunnelService, pathKind.name, "socks_not_ready")
                    failAndStop("SOCKS not ready")
                    return@fold
                }
                val probeStart = System.currentTimeMillis()
                val probe = ConnectivityProbe.probeThroughSocks(socksPort)
                val probeRtt = System.currentTimeMillis() - probeStart
                if (probe.isFailure) {
                    LocalFailureLog.record(
                        this@VpnTunnelService,
                        pathKind.name,
                        "probe_failed",
                        probeRtt,
                    )
                    runner?.disconnect()
                    failAndStop("Probe failed: ${probe.exceptionOrNull()?.message}")
                    return@fold
                }
                if (!running) {
                    runner?.disconnect()
                    return@fold
                }
                val listToSave = fetchedList
                val pathLabel = pathKind.name.lowercase().replaceFirstChar { it.uppercase() }
                if (!establishTun(socksPort, socks?.supportsUdp() == true, reuseTun = reuseTun)) {
                    failAndStop("TUN establish failed")
                    return@fold
                }
                if (!PacketForwarder.isForwarding) {
                    failAndStop("Packet forwarder not running")
                    return@fold
                }
                runOnMain {
                    if (!running) {
                        PacketForwarder.stop()
                        runner?.disconnect()
                        isConnected = false
                        isConnecting = false
                        return@runOnMain
                    }
                    activePathName = pathLabel
                    isConnected = true
                    isConnecting = false
                    if (listToSave != null) {
                        ConfigFetcher.saveLastGood(this@VpnTunnelService, listToSave)
                    }
                    updateNotification("Connected via $activePathName")
                    startHealthLoop(socksPort)
                }
            },
            onFailure = {
                if (!running) return@fold
                LocalFailureLog.record(this@VpnTunnelService, "race", it.message ?: "all_failed")
                failAndStop(it.message ?: "all paths failed")
            }
        )
    }

    private fun startAsForeground(status: String) {
        val notification = createNotification(status)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            ServiceCompat.startForeground(
                this,
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
            )
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, notification)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun failAndStop(msg: String) {
        runOnMain {
            updateNotification("Failed: $msg")
            isConnected = false
            isConnecting = false
            running = false
            activePathName = null
            activeRunner?.disconnect()
            activeRunner = null
            PacketForwarder.stop()
            tunnelFd?.close()
            tunnelFd = null
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
        }
    }

    private fun runOnMain(block: () -> Unit) {
        android.os.Handler(android.os.Looper.getMainLooper()).post(block)
    }

    private fun establishTun(socksPort: Int, forwardUdp: Boolean, reuseTun: Boolean = false): Boolean {
        if (!reuseTun || tunnelFd == null) {
            tunnelFd?.close()
            tunnelFd = null
            val builder = Builder()
                .setSession("IranVPN")
                .setMtu(PacketForwarder.DEFAULT_MTU)
                .addAddress("10.0.0.2", 24)
                .addRoute("0.0.0.0", 0)
                // Prefer UDP-capable DNS only when forwardUdp; otherwise keep fake-IP
                // style DNS to avoid cleartext UDP DNS leaks outside the tunnel.
                .addDnsServer(if (forwardUdp) "1.1.1.1" else "198.18.0.2")
                .setBlocking(false)

            // Only claim full IPv6 when tun2socks can forward UDP/IPv6 meaningfully.
            // Without a default IPv6 route, leave IPv6 on the underlay (avoids blackhole).
            if (forwardUdp) {
                try {
                    builder.addAddress("fd00:0:0:1::2", 64)
                    builder.addRoute("::", 0)
                    builder.addDnsServer("2606:4700:4700::1111")
                } catch (_: Exception) {}
            }

            try {
                builder.addDisallowedApplication(packageName)
            } catch (e: Exception) {
                android.util.Log.w(TAG, "addDisallowedApplication failed: ${e.message}")
            }

            tunnelFd = builder.establish()
            if (tunnelFd == null) {
                activeRunner?.disconnect()
                return false
            }
        }

        // Allow forwarder to stay alive while isConnected flips true after return.
        val ok = PacketForwarder.start(
            tunnelFd!!,
            socksPort,
            mtu = PacketForwarder.DEFAULT_MTU,
            forwardUdp = forwardUdp,
        ) { running }
        if (!ok) {
            if (!reuseTun) {
                tunnelFd?.close()
                tunnelFd = null
            }
            activeRunner?.disconnect()
            return false
        }
        // Brief settle so native tun2socks can fail fast before we claim Connected.
        try {
            Thread.sleep(300)
        } catch (_: InterruptedException) {}
        if (!PacketForwarder.isForwarding) {
            if (!reuseTun) {
                tunnelFd?.close()
                tunnelFd = null
            }
            activeRunner?.disconnect()
            return false
        }
        return true
    }

    private fun startHealthLoop(socksPort: Int) {
        healthThread?.interrupt()
        healthThread = thread(name = "vpn-health") {
            var failures = 0
            while (running && isConnected) {
                try {
                    Thread.sleep(5_000)
                } catch (_: InterruptedException) {
                    break
                }
                if (!running || !isConnected) break
                val port = (activeRunner as? SocksProxyProvider)?.getLocalSocksPort() ?: socksPort
                val probe = ConnectivityProbe.probeThroughSocks(port)
                if (probe.isFailure) {
                    failures++
                    android.util.Log.w(TAG, "health probe failed ($failures): ${probe.exceptionOrNull()?.message}")
                    if (failures >= 2 || !PacketForwarder.isForwarding) {
                        // Keep TUN up; soft-reconnect races a new path under kill switch.
                        PacketForwarder.stop()
                        isConnected = false
                        runOnMain { updateNotification("Reconnecting…") }
                        val intent = Intent(this@VpnTunnelService, VpnTunnelService::class.java).apply {
                            action = ACTION_RECONNECT
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        break
                    }
                } else if (!PacketForwarder.isForwarding) {
                    failures++
                } else {
                    failures = 0
                }
            }
        }
    }

    /** @param stop if true, stop the service; if false, tear down for reconnect. */
    private fun disconnect(stop: Boolean) {
        running = false
        isConnected = false
        isConnecting = false
        activePathName = null
        healthThread?.interrupt()
        healthThread = null
        PacketForwarder.stop()
        activeRunner?.disconnect()
        activeRunner = null
        tunnelFd?.close()
        tunnelFd = null
        if (stop) {
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
        }
    }

    override fun onDestroy() {
        disconnect(stop = false)
        super.onDestroy()
    }

    private fun createNotification(status: String): Notification {
        createChannel()
        val pending = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Iran VPN")
            .setContentText(status)
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setContentIntent(pending)
            .setOngoing(true)
            .build()
    }

    private fun updateNotification(status: String) {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(NOTIFICATION_ID, createNotification(status))
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(
                CHANNEL_ID,
                "VPN",
                NotificationManager.IMPORTANCE_LOW
            ).apply { setShowBadge(false) }
            (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                .createNotificationChannel(ch)
        }
    }

    companion object {
        private const val TAG = "VpnTunnelService"
        const val ACTION_CONNECT = "org.opensignalfoundation.iranvpn.CONNECT"
        const val ACTION_DISCONNECT = "org.opensignalfoundation.iranvpn.DISCONNECT"
        const val ACTION_RECONNECT = "org.opensignalfoundation.iranvpn.RECONNECT"
        private const val CHANNEL_ID = "iran_vpn_channel"
        private const val NOTIFICATION_ID = 1

        @Volatile
        var isConnected = false
            private set

        @Volatile
        var isConnecting = false
            private set

        @Volatile
        var activePathName: String? = null
            private set

        fun disconnect(context: Context) {
            context.startService(Intent(context, VpnTunnelService::class.java).apply {
                action = ACTION_DISCONNECT
            })
        }
    }
}
