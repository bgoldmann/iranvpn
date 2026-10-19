package org.opensignalfoundation.iranvpn.fallback

import org.opensignalfoundation.iranvpn.model.PathConfig

/**
 * Conduit is built into the Psiphon SDK — do not use this as a standalone path.
 * Kept for config compatibility; always redirects callers to use Psiphon.
 */
class ConduitPathRunner : PathRunner {
    override fun connect(config: PathConfig): PathResult {
        return PathResult.Failure(
            "Conduit is included in Psiphon — use the Psiphon path (zero-config includes Conduit P2P)"
        )
    }

    override fun disconnect() {
        // no-op
    }
}
