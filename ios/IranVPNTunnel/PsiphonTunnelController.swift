#if PATH_PSIPHON
import Foundation
import PsiphonTunnel

/// Wraps PsiphonTunnel (Go) — local SOCKS only; never link alongside LibXray in this process.
final class PsiphonTunnelController: NSObject, TunneledAppDelegate {
    private var tunnel: PsiphonTunnel?
    private var socksPortContinuation: CheckedContinuation<Int, Error>?
    private let lock = NSLock()
    private var finished = false
    private(set) var socksPort: Int = 0

    func start() async throws -> Int {
        socksPort = 0
        finished = false
        let tunnel = PsiphonTunnel.newPsiphonTunnel(self)
        self.tunnel = tunnel
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Int, Error>) in
            self.lock.lock()
            self.socksPortContinuation = cont
            self.lock.unlock()
            let ok = tunnel.start(false)
            if !ok {
                self.resumeSocks(throwing: TunnelError.pathUnavailable)
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 90) { [weak self] in
                self?.resumeSocks(throwing: TunnelError.probeFailed)
            }
        }
    }

    func stop() {
        tunnel?.stop()
        tunnel = nil
        socksPort = 0
    }

    private func resumeSocks(returning port: Int) {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }
        finished = true
        socksPort = port
        let c = socksPortContinuation
        socksPortContinuation = nil
        c?.resume(returning: port)
    }

    private func resumeSocks(throwing error: Error) {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }
        finished = true
        let c = socksPortContinuation
        socksPortContinuation = nil
        c?.resume(throwing: error)
    }

    // MARK: - TunneledAppDelegate

    func getPsiphonConfig() -> Any? {
        // Sample Propagation/Sponsor IDs from psiphon-tunnel-core public client.config.
        // Replace with your own credentials from Psiphon Inc for production.
        [
            "PropagationChannelId": "24BCA4EE20BEB92C",
            "SponsorId": "721AE60D76700F5A",
            "EmitDiagnosticNotices": false,
            "EstablishTunnelTimeoutSeconds": 60,
            "LocalSocksProxyPort": 0,
            "LocalHttpProxyPort": 0,
            "DisableLocalSocksAuth": true,
        ] as [String: Any]
    }

    func getEmbeddedServerEntries() -> String? { "" }

    func onListeningSocksProxyPort(_ port: Int) {
        if port > 0 {
            resumeSocks(returning: port)
        }
    }

    func onConnected() {
        let port = Int(tunnel?.getLocalSocksProxyPort() ?? 0)
        if port > 0 {
            resumeSocks(returning: port)
        }
    }

    func onExiting() {}

    func onDiagnosticMessage(_ message: String, withTimestamp timestamp: String) {
        _ = (message, timestamp)
    }
}
#endif
