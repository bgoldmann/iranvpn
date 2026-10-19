import Foundation
import NetworkExtension
import Observation

/// Manages NETunnelProviderManager — never reports Connected without system VPN status.
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
            if let activePath {
                return "متصل از طریق \(activePath) / Connected via \(activePath)"
            }
            return "متصل / Connected"
        }
        return "قطع / Disconnected"
    }

    /// Psiphon extension (default). Separate from Xray because both embed a Go runtime.
    private let psiphonTunnelBundleId = "com.goldmannllc.IranVPN.tunnel"
    private let xrayTunnelBundleId = "com.goldmannllc.IranVPN.tunnel.xray"
    /// Stored for removal in `deinit` (nonisolated).
    private nonisolated(unsafe) var statusObserver: NSObjectProtocol?

    private var preferredTunnelBundleId: String {
        if let link = importedShareLink, !link.isEmpty {
            return xrayTunnelBundleId
        }
        return psiphonTunnelBundleId
    }

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
            guard let manager = managers.first else {
                isConnected = false
                isConnecting = false
                return
            }
            switch manager.connection.status {
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
            let bundleId = preferredTunnelBundleId
            let manager = try await loadOrCreateManager(bundleId: bundleId)
            try await manager.loadFromPreferences()
            manager.isEnabled = true
            if let proto = manager.protocolConfiguration as? NETunnelProviderProtocol {
                var providerConfig = proto.providerConfiguration ?? [:]
                if let link = importedShareLink, !link.isEmpty {
                    providerConfig["share_link"] = link
                } else {
                    providerConfig.removeValue(forKey: "share_link")
                }
                providerConfig["bootstrap"] = "embedded"
                proto.providerConfiguration = providerConfig
                proto.providerBundleIdentifier = bundleId
                manager.protocolConfiguration = proto
            }
            try await manager.saveToPreferences()
            try await manager.loadFromPreferences()
            manager.isEnabled = true
            try await manager.saveToPreferences()
            try await manager.loadFromPreferences()

            try manager.connection.startVPNTunnel()
            let intendedPath = importedShareLink?.isEmpty == false ? "Xray" : "Psiphon"

            // Allow status to leave .disconnected before treating it as failure
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
                // Only abort on disconnected after we have seen connecting, or after grace period
                if sawActivity && (status == .disconnected || status == .invalid) {
                    break
                }
                if !sawActivity && i >= 6 && (status == .invalid) {
                    break
                }
            }
            isConnecting = false
            activePath = nil
            if !isConnected {
                errorMessage =
                    "Tunnel did not connect — run scripts/fetch-ios-tunnel-deps.sh, embed \(preferredTunnelBundleId), and enable Network Extension signing."
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
            managers.first?.connection.stopVPNTunnel()
        } catch {}
        isConnected = false
        isConnecting = false
        activePath = nil
    }

    private func loadOrCreateManager(bundleId: String) async throws -> NETunnelProviderManager {
        let existing = try await NETunnelProviderManager.loadAllFromPreferences()
        if let manager = existing.first(where: {
            ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == bundleId
        }) ?? existing.first {
            manager.isEnabled = true
            return manager
        }
        let manager = NETunnelProviderManager()
        let proto = NETunnelProviderProtocol()
        proto.providerBundleIdentifier = bundleId
        proto.serverAddress = "IranVPN"
        manager.protocolConfiguration = proto
        manager.localizedDescription = bundleId.contains("xray") ? "Iran VPN (Xray)" : "Iran VPN"
        manager.isEnabled = true
        try await manager.saveToPreferences()
        try await manager.loadFromPreferences()
        manager.isEnabled = true
        return manager
    }
}

