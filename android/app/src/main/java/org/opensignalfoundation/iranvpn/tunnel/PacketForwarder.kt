package org.opensignalfoundation.iranvpn.tunnel

import android.os.ParcelFileDescriptor
import java.io.FileInputStream
import java.nio.ByteBuffer
import kotlin.concurrent.thread

/**
 * Forwards TUN traffic through SOCKS5 via tun2socks.
 * Kill switch: if socksPort <= 0, drop all packets (do not claim connectivity).
 */
object PacketForwarder {

    const val DEFAULT_MTU = 1280
    const val DEFAULT_NET_IPV4 = "10.0.0.2"
    const val DEFAULT_NETMASK = "255.255.255.0"

    @Volatile
    private var forwarding = false

    val isForwarding: Boolean get() = forwarding

    /**
     * Start forwarding. Requires socksPort > 0; otherwise runs a drop loop (kill switch).
     *
     * @return false if socksPort was invalid (caller should treat as failed connect)
     */
    @JvmOverloads
    fun start(
        tunFd: ParcelFileDescriptor,
        socksPort: Int,
        mtu: Int = DEFAULT_MTU,
        netIPv4: String = DEFAULT_NET_IPV4,
        netmask: String = DEFAULT_NETMASK,
        forwardUdp: Boolean = false,
        running: () -> Boolean,
    ): Boolean {
        stop()
        if (socksPort <= 0) {
            // Kill switch: drop packets; never silently blackhole while claiming "connected"
            forwarding = false
            thread(name = "vpn-tun-killswitch") {
                runReadLoop(tunFd, running) { /* drop */ }
            }
            return false
        }
        forwarding = true
        thread(name = "vpn-tun2socks") {
            try {
                val exitCode = Tun2SocksNative.startTun2Socks(
                    tunFd = tunFd,
                    mtu = mtu,
                    socksHost = "127.0.0.1",
                    socksPort = socksPort,
                    netIPv4 = netIPv4,
                    netIPv6 = null,
                    netmask = netmask,
                    forwardUdp = forwardUdp,
                    logLevel = 3,
                )
                forwarding = false
                if (exitCode != 0 && running()) {
                    android.util.Log.w("PacketForwarder", "tun2socks exited with code $exitCode")
                }
            } catch (e: Throwable) {
                forwarding = false
                if (running()) {
                    android.util.Log.e("PacketForwarder", "tun2socks failed", e)
                }
            }
        }
        return true
    }

    fun stop() {
        forwarding = false
        Tun2SocksNative.stopTun2Socks()
    }

    private fun runReadLoop(
        pfd: ParcelFileDescriptor,
        running: () -> Boolean,
        onPacket: (ByteBuffer) -> Unit,
    ) {
        val channel = FileInputStream(pfd.fileDescriptor).channel
        val buffer = ByteBuffer.allocate(32767)
        while (running() && pfd.fileDescriptor.valid()) {
            buffer.clear()
            val n = channel.read(buffer)
            if (n <= 0) {
                try {
                    Thread.sleep(1)
                } catch (_: InterruptedException) {
                    break
                }
                continue
            }
            buffer.flip()
            val copy = ByteBuffer.allocate(buffer.remaining())
            copy.put(buffer)
            copy.flip()
            onPacket(copy)
        }
    }
}
