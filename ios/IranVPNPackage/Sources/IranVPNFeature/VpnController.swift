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
    var importedShareLink: String? {
        didSet { persistShareLink() }
    }

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
    private let shareLinkKey = "importedShareLink"

    /// True when the Xray Packet Tunnel appex was embedded in this build.
    var xrayExtensionAvailable: Bool {
        guard let plugins = Bundle.main.builtInPlugInsURL else { return false }
        return FileManager.default.fileExists(
            atPath: plugins.appendingPathComponent("IranVPNTunnelXray.appex").path
        )
    }
    /// Stored for removal in `deinit` (nonisolated).
    private nonisolated(unsafe) var statusObserver: NSObjectProtocol?

    private var preferredTunnelBundleId: String {
        if xrayExtensionAvailable, let link = importedShareLink, !link.isEmpty {
            return xrayTunnelBundleId
        }
        return psiphonTunnelBundleId
    }

    init() {
        importedShareLink = UserDefaults.standard.string(forKey: shareLinkKey)
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

    func clearShareLink() {
        importedShareLink = nil
    }

    func refreshStatus() async {
        do {
            let managers = try await NETunnelProviderManager.loadAllFromPreferences()
            let manager = preferredManager(from: managers)
            guard let manager else {
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
            let bundleId = preferredTunnelBundleId
            // Stop the other path's tunnel if it is still up.
            try await stopOtherTunnels(except: bundleId)

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

            var sawActivity = false
            for i in 0..<120 {
                try await Task.sleep(for: .milliseconds(500))
                let status = manager.connection.status
                apply(status: status)
                if status == .connecting || status == .reasserting || status == .connected {
                    sawActivity = true
                }
                if status == .connected {
                    activePath = intendedPath
                    isConnecting = false
                    isConnected = true
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
                errorMessage =
                    "Tunnel did not connect — run scripts/fetch-ios-tunnel-deps.sh, embed \(bundleId), and enable Network Extension signing."
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
            let bundleId = preferredTunnelBundleId
            if let manager = preferredManager(from: managers, bundleId: bundleId) {
                manager.connection.stopVPNTunnel()
            } else {
                // Fall back: stop any Iran VPN tunnel that is active.
                for manager in managers where isIranVPN(manager) {
                    manager.connection.stopVPNTunnel()
                }
            }
        } catch {}
        isConnected = false
        isConnecting = false
        activePath = nil
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

    private func preferredManager(
        from managers: [NETunnelProviderManager],
        bundleId: String? = nil
    ) -> NETunnelProviderManager? {
        let id = bundleId ?? preferredTunnelBundleId
        if let exact = managers.first(where: {
            ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == id
        }) {
            return exact
        }
        // Prefer any connected Iran VPN manager over an arbitrary first entry.
        if let connected = managers.first(where: {
            isIranVPN($0) && $0.connection.status == .connected
        }) {
            return connected
        }
        return managers.first(where: isIranVPN)
    }

    private func isIranVPN(_ manager: NETunnelProviderManager) -> Bool {
        guard let id = (manager.protocolConfiguration as? NETunnelProviderProtocol)?
            .providerBundleIdentifier
        else { return false }
        return id == psiphonTunnelBundleId || id == xrayTunnelBundleId
    }

    private func stopOtherTunnels(except bundleId: String) async throws {
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        for manager in managers {
            guard let id = (manager.protocolConfiguration as? NETunnelProviderProtocol)?
                .providerBundleIdentifier,
                id != bundleId,
                isIranVPN(manager)
            else { continue }
            if manager.connection.status != .disconnected && manager.connection.status != .invalid {
                manager.connection.stopVPNTunnel()
            }
        }
    }

    private func loadOrCreateManager(bundleId: String) async throws -> NETunnelProviderManager {
        let existing = try await NETunnelProviderManager.loadAllFromPreferences()
        if let manager = existing.first(where: {
            ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == bundleId
        }) {
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

    private func persistShareLink() {
        if let link = importedShareLink, !link.isEmpty {
            UserDefaults.standard.set(link, forKey: shareLinkKey)
        } else {
            UserDefaults.standard.removeObject(forKey: shareLinkKey)
        }
    }
}
