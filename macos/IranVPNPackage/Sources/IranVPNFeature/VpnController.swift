import Foundation
import NetworkExtension
import Observation

@Observable
@MainActor
final class VpnController {
    var isConnected = false
    var isConnecting = false
    var activePath: String?
    var errorMessage: String?
    var importedShareLink: String?

    var statusText: String {
        if isConnecting { return "در حال اتصال… / Connecting…" }
        if isConnected {
            return activePath.map { "Connected via \($0)" } ?? "متصل / Connected"
        }
        return "قطع / Disconnected"
    }

    private let tunnelBundleId = "com.goldmannllc.IranVPN.tunnel"
    /// Stored for removal in `deinit` (nonisolated).
    private nonisolated(unsafe) var statusObserver: NSObjectProtocol?

    init() {
        statusObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshStatus()
            }
        }
    }

    deinit {
        if let statusObserver {
            NotificationCenter.default.removeObserver(statusObserver)
        }
    }

    func refreshStatus() async {
        do {
            let managers = try await NETunnelProviderManager.loadAllFromPreferences()
            guard let manager = managers.first(where: { matchesTunnel($0) }) else {
                isConnected = false
                isConnecting = false
                return
            }
            apply(status: manager.connection.status)
        } catch {
            isConnected = false
            isConnecting = false
        }
    }

    func connect() async {
        errorMessage = nil
        isConnecting = true
        isConnected = false
        activePath = nil
        do {
            let manager = try await loadOrCreateManager()
            try await manager.loadFromPreferences()
            manager.isEnabled = true
            if let proto = manager.protocolConfiguration as? NETunnelProviderProtocol {
                var cfg = proto.providerConfiguration ?? [:]
                if let link = importedShareLink, !link.isEmpty {
                    cfg["share_link"] = link
                } else {
                    cfg.removeValue(forKey: "share_link")
                }
                proto.providerConfiguration = cfg
                proto.providerBundleIdentifier = tunnelBundleId
                manager.protocolConfiguration = proto
            }
            try await manager.saveToPreferences()
            try await manager.loadFromPreferences()
            manager.isEnabled = true
            try await manager.saveToPreferences()
            try await manager.loadFromPreferences()

            try manager.connection.startVPNTunnel()
            let intendedPath = "Psiphon"

            var sawActivity = false
            for i in 0..<60 {
                try await Task.sleep(for: .milliseconds(500))
                await refreshStatus()
                let status = manager.connection.status
                if status == .connecting || status == .reasserting || status == .connected {
                    sawActivity = true
                }
                if isConnected {
                    activePath = intendedPath
                    isConnecting = false
                    return
                }
                if sawActivity && (status == .disconnected || status == .invalid) {
                    break
                }
                if !sawActivity && i >= 6 && status == .invalid {
                    break
                }
            }
            isConnecting = false
            activePath = nil
            if !isConnected {
                errorMessage = "Tunnel did not connect — enable Network Extension entitlement and embed com.goldmannllc.IranVPN.tunnel."
            }
        } catch {
            isConnecting = false
            isConnected = false
            activePath = nil
            errorMessage = error.localizedDescription
        }
    }

    func disconnect() async {
        do {
            let managers = try await NETunnelProviderManager.loadAllFromPreferences()
            managers.first(where: { matchesTunnel($0) })?.connection.stopVPNTunnel()
        } catch {}
        isConnected = false
        isConnecting = false
        activePath = nil
    }

    func clearShareLink() {
        importedShareLink = nil
    }

    private func apply(status: NEVPNStatus) {
        switch status {
        case .connected:
            isConnected = true
            isConnecting = false
        case .connecting, .reasserting:
            isConnecting = true
            isConnected = false
        default:
            isConnected = false
            isConnecting = false
        }
    }

    private func matchesTunnel(_ manager: NETunnelProviderManager) -> Bool {
        guard let proto = manager.protocolConfiguration as? NETunnelProviderProtocol,
              let id = proto.providerBundleIdentifier else { return false }
        return id == tunnelBundleId
    }

    private func loadOrCreateManager() async throws -> NETunnelProviderManager {
        let existing = try await NETunnelProviderManager.loadAllFromPreferences()
        if let manager = existing.first(where: { matchesTunnel($0) }) {
            manager.isEnabled = true
            return manager
        }
        let manager = NETunnelProviderManager()
        let proto = NETunnelProviderProtocol()
        proto.providerBundleIdentifier = tunnelBundleId
        proto.serverAddress = "IranVPN"
        manager.protocolConfiguration = proto
        manager.localizedDescription = "Iran VPN"
        manager.isEnabled = true
        try await manager.saveToPreferences()
        try await manager.loadFromPreferences()
        manager.isEnabled = true
        return manager
    }
}
