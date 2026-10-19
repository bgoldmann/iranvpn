package org.opensignalfoundation.iranvpn.fallback

import org.opensignalfoundation.iranvpn.model.PathConfig

/**
 * RostamWG (obfuscated WireGuard) — excluded from the default race.
 * Raw UDP WireGuard loses to Iran's protocol whitelist; only enable when
 * the path sits behind TLS or the user explicitly imports a Rostam config
 * that uses an allowed outer transport.
 */
class RostamPathRunner : PathRunner {
    override fun connect(config: PathConfig): PathResult {
        if (config !is PathConfig.RostamConfig) return PathResult.Failure("wrong config type")
        return PathResult.Failure(
            "Rostam not in default chain (UDP WireGuard blocked by whitelist). " +
                "Import a VLESS+REALITY or use Psiphon instead."
        )
    }

    override fun disconnect() {
        // no-op until TLS-wrapped Rostam is available
    }
}
