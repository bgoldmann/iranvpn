package org.opensignalfoundation.iranvpn.fallback

import android.content.Context
import org.opensignalfoundation.iranvpn.model.PathConfig

/**
 * AmneziaWG — Advanced-only until a SOCKS-capable helper is bundled.
 * Raw UDP WireGuard / AWG needs a userspace stack (e.g. amneziawg-go) that
 * exposes local SOCKS for our TUN forwarder — not wired yet.
 */
class AmneziaWgPathRunner(private val context: Context) : PathRunner {
    override fun connect(config: PathConfig): PathResult {
        if (config !is PathConfig.AmneziaWgConfig) return PathResult.Failure("wrong config type")
        if (config.config.isBlank()) return PathResult.Failure("empty AmneziaWG config")
        val hasBin = AssetBinary.hasAny(
            context,
            listOf("amneziawg/\$ABI/amneziawg-go", "amneziawg/amneziawg-go", "awg/\$ABI/awg"),
        )
        return if (!hasBin) {
            PathResult.Failure(
                "AmneziaWG helper not bundled yet — import VLESS+REALITY or use Psiphon. " +
                    "Add assets/amneziawg/<abi>/amneziawg-go when ready.",
            )
        } else {
            PathResult.Failure(
                "AmneziaWG binary present but SOCKS bridge not implemented — coming next.",
            )
        }
    }

    override fun disconnect() {}
}
