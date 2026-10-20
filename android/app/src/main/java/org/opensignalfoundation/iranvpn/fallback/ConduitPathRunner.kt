package org.opensignalfoundation.iranvpn.fallback

import org.opensignalfoundation.iranvpn.model.PathConfig

/**
 * Conduit is Psiphon in-proxy — not a standalone race path.
 * Personal compartment IDs are applied via [org.opensignalfoundation.iranvpn.ConduitPrefs]
 * into [PsiphonPathRunner] config.
 */
class ConduitPathRunner : PathRunner {
    override fun connect(config: PathConfig): PathResult {
        val compartment = (config as? PathConfig.ConduitConfig)?.personalCompartmentId
        return PathResult.Failure(
            if (!compartment.isNullOrBlank()) {
                "Conduit pairing is applied on the Psiphon path — save compartment in Advanced, then Connect"
            } else {
                "Conduit is included in Psiphon (in-proxy) — use Psiphon Connect; optional personal code in Advanced"
            },
        )
    }

    override fun disconnect() {}
}
