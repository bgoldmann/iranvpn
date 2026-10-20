#if PATH_PSIPHON
import Foundation
import PsiphonTunnel

/// Wraps PsiphonTunnel (Go) — local SOCKS only; never link alongside LibXray in this process.
/// Config loading follows Psiphon TunneledWebRequest: bundle JSON + embedded server entries file.
/// `@unchecked Sendable`: state is guarded by `lock`; Psiphon callbacks arrive off the main actor.
final class PsiphonTunnelController: NSObject, TunneledAppDelegate, @unchecked Sendable {
    private var tunnel: PsiphonTunnel?
    private var socksPortContinuation: CheckedContinuation<Int, Error>?
    private let lock = NSLock()
    private var finished = false
    private var listeningPort: Int = 0
    private(set) var socksPort: Int = 0
    /// Optional Conduit personal pairing (InproxyClientPersonalCompartmentID).
    var personalCompartmentId: String?

    func start() async throws -> Int {
        socksPort = 0
        listeningPort = 0
        finished = false
        let tunnel = PsiphonTunnel.newPsiphonTunnel(self)
        self.tunnel = tunnel
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Int, Error>) in
            self.lock.lock()
            self.socksPortContinuation = cont
            self.lock.unlock()
            // start(false): always (re)start — correct inside NEPacketTunnelProvider.
            let ok = tunnel.start(false)
            if !ok {
                self.resumeSocks(throwing: TunnelError.pathUnavailable)
                return
            }
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(90))
                self?.resumeSocks(throwing: TunnelError.probeFailed)
            }
        }
    }

    func stop() {
        resumeSocks(throwing: CancellationError())
        tunnel?.stop()
        tunnel = nil
        socksPort = 0
        listeningPort = 0
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

    // MARK: - Config (TunneledWebRequest pattern)

    private func loadBundledConfig() -> [String: Any]? {
        let bundle = Bundle(for: PsiphonTunnelController.self)
        guard let url = bundle.url(forResource: "psiphon-config", withExtension: "json", subdirectory: "Resources")
            ?? bundle.url(forResource: "psiphon-config", withExtension: "json")
        else {
            return nil
        }
        guard let data = try? Data(contentsOf: url),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        // Optional local override (distributor secrets) — not committed.
        if let localURL = bundle.url(forResource: "psiphon-config.local", withExtension: "json", subdirectory: "Resources")
            ?? bundle.url(forResource: "psiphon-config.local", withExtension: "json"),
           let localData = try? Data(contentsOf: localURL),
           let local = try? JSONSerialization.jsonObject(with: localData) as? [String: Any]
        {
            json.merge(local) { _, new in new }
        }
        // Writable datastore inside the Network Extension container.
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let store = support.appendingPathComponent("psiphon-datastore", isDirectory: true)
        try? FileManager.default.createDirectory(at: store, withIntermediateDirectories: true)
        json["DataStoreDirectory"] = store.path
        if let compartment = personalCompartmentId, !compartment.isEmpty {
            json["InproxyClientPersonalCompartmentID"] = compartment
        }
        return json
    }

    // MARK: - TunneledAppDelegate

    func getPsiphonConfig() -> Any? {
        if let bundled = loadBundledConfig() {
            return bundled
        }
        // Fallback if Resources were not copied into the appex.
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let store = support.appendingPathComponent("psiphon-datastore", isDirectory: true)
        try? FileManager.default.createDirectory(at: store, withIntermediateDirectories: true)
        var fallback: [String: Any] = [
            "ClientVersion": "1",
            "PropagationChannelId": "07D1ACD69B3AC7A2",
            "SponsorId": "EE0B7486ACAE75AA",
            "EmitDiagnosticNotices": true,
            "EstablishTunnelTimeoutSeconds": 120,
            "LocalSocksProxyPort": 0,
            "LocalHttpProxyPort": 0,
            "DisableLocalSocksAuth": true,
            "DataStoreDirectory": store.path,
        ]
        if let compartment = personalCompartmentId, !compartment.isEmpty {
            fallback["InproxyClientPersonalCompartmentID"] = compartment
        }
        return fallback
    }

    func getEmbeddedServerEntries() -> String? {
        let bundle = Bundle(for: PsiphonTunnelController.self)
        // Prefer gitignored local file (full extract) over committed bootstrap subset.
        let candidates: [(String, String?)] = [
            ("psiphon-embedded-server-entries.local", "txt"),
            ("psiphon-embedded-server-entries", "txt"),
        ]
        for (name, ext) in candidates {
            if let url = bundle.url(forResource: name, withExtension: ext, subdirectory: "Resources")
                ?? bundle.url(forResource: name, withExtension: ext),
               let text = try? String(contentsOf: url, encoding: .utf8),
               text.contains(where: { !$0.isWhitespace })
            {
                NSLog("[Psiphon] loaded embedded server entries from %@ (%d bytes)", url.lastPathComponent, text.utf8.count)
                return text
            }
        }
        NSLog("[Psiphon] WARNING: no embedded server entries in bundle — tunnel will not establish without RemoteServerList")
        return ""
    }

    func onListeningSocksProxyPort(_ port: Int) {
        if port > 0 {
            listeningPort = port
        }
    }

    func onConnected() {
        let port = Int(tunnel?.getLocalSocksProxyPort() ?? 0)
        let resolved = port > 0 ? port : listeningPort
        if resolved > 0 {
            resumeSocks(returning: resolved)
        }
    }

    func onExiting() {
        resumeSocks(throwing: TunnelError.pathUnavailable)
    }

    func onDiagnosticMessage(_ message: String, withTimestamp timestamp: String) {
        NSLog("[Psiphon] %@ %@", timestamp, message)
    }
}
#endif
