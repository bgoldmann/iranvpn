import Foundation
import NetworkExtension
import Observation

/// Holds the NEVPN observer token so `deinit` need not touch MainActor/`@Observable` state.
private final class VpnStatusObserverBox: @unchecked Sendable {
    var token: NSObjectProtocol?

    func invalidate() {
        if let token {
            NotificationCenter.default.removeObserver(token)
            self.token = nil
        }
    }
}

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
    @ObservationIgnored
    private let statusObserver = VpnStatusObserverBox()
    @ObservationIgnored
    private var networkExtensionDenied = false
    @ObservationIgnored
    private var connectGeneration = 0

    init() {}

    deinit {
        statusObserver.invalidate()
    }

    func refreshStatus() async {
        guard !networkExtensionDenied else { return }
        do {
            let managers = try await NETunnelProviderManager.loadAllFromPreferences()
            installStatusObserverIfNeeded()
            guard let manager = managers.first(where: { matchesTunnel($0) }) else {
                isConnected = false
                isConnecting = false
                return
            }
            apply(status: manager.connection.status)
        } catch {
            isConnected = false
            isConnecting = false
            handleConfigurationError(error)
        }
    }

    func connect() async {
        errorMessage = nil
        if networkExtensionDenied {
            errorMessage = Self.networkExtensionSetupMessage
            return
        }
        connectGeneration += 1
        let generation = connectGeneration
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
                if let compartment = UserDefaults.standard.string(forKey: "conduitPersonalCompartment"),
                   !compartment.isEmpty
                {
                    cfg["InproxyClientPersonalCompartmentID"] = compartment
                } else {
                    cfg.removeValue(forKey: "InproxyClientPersonalCompartmentID")
                }
                cfg["bootstrap"] = "embedded"
                proto.providerConfiguration = cfg
                proto.providerBundleIdentifier = tunnelBundleId
                manager.protocolConfiguration = proto
            }
            try await manager.saveToPreferences()
            try await manager.loadFromPreferences()
            manager.isEnabled = true
            try await manager.saveToPreferences()
            try await manager.loadFromPreferences()

            try await ensureTunnelStopped(manager)
            guard generation == connectGeneration else { return }

            try manager.connection.startVPNTunnel()
            installStatusObserverIfNeeded()
            let intendedPath = "Psiphon"

            var sawActivity = false
            for i in 0..<120 {
                guard generation == connectGeneration else {
                    isConnecting = false
                    return
                }
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
            guard generation == connectGeneration else { return }
            isConnecting = false
            activePath = nil
            if !isConnected {
                errorMessage = "Tunnel did not connect — enable Network Extension entitlement and embed com.goldmannllc.IranVPN.tunnel."
            }
        } catch {
            guard generation == connectGeneration else { return }
            isConnecting = false
            isConnected = false
            activePath = nil
            if isNetworkExtensionPermissionDenied(error) {
                handleConfigurationError(error)
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    func disconnect() async {
        connectGeneration += 1
        errorMessage = nil
        isConnected = false
        isConnecting = false
        activePath = nil
        guard !networkExtensionDenied else { return }
        do {
            let managers = try await NETunnelProviderManager.loadAllFromPreferences()
            if let manager = managers.first(where: { matchesTunnel($0) }) {
                manager.connection.stopVPNTunnel()
                await waitUntilTunnelStopped(manager)
            }
        } catch {
            handleConfigurationError(error)
        }
        isConnected = false
        isConnecting = false
        activePath = nil
    }

    private func ensureTunnelStopped(_ manager: NETunnelProviderManager) async throws {
        let status = manager.connection.status
        if status == .disconnected || status == .invalid { return }
        manager.connection.stopVPNTunnel()
        await waitUntilTunnelStopped(manager)
    }

    private func waitUntilTunnelStopped(_ manager: NETunnelProviderManager) async {
        for _ in 0..<50 {
            let status = manager.connection.status
            if status == .disconnected || status == .invalid { return }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    func clearShareLink() {
        importedShareLink = nil
    }

    private static let networkExtensionSetupMessage =
        "VPN not available — Packet Tunnel entitlement missing. Enable it on the Mac App IDs, set IRANVPN_ENTITLEMENTS_SUFFIX=-NetworkExtension in macos/Config/NetworkExtension.xcconfig, rebuild."

    private func installStatusObserverIfNeeded() {
        guard statusObserver.token == nil, !networkExtensionDenied else { return }
        statusObserver.token = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let status = (notification.object as? NEVPNConnection)?.status
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let status {
                    self.apply(status: status)
                } else {
                    await self.refreshStatus()
                }
            }
        }
    }

    private func handleConfigurationError(_ error: Error) {
        guard isNetworkExtensionPermissionDenied(error) else { return }
        networkExtensionDenied = true
        statusObserver.invalidate()
        errorMessage = Self.networkExtensionSetupMessage
    }

    private func isNetworkExtensionPermissionDenied(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == "NEConfigurationErrorDomain", ns.code == 10 { return true }
        return ns.localizedDescription.localizedCaseInsensitiveContains("permission denied")
    }

    private func apply(status: NEVPNStatus) {
        switch status {
        case .connected:
            isConnected = true
            isConnecting = false
        case .connecting, .reasserting:
            isConnecting = true
            isConnected = false
        case .disconnecting:
            isConnected = false
            isConnecting = false
        case .disconnected, .invalid:
            isConnected = false
            isConnecting = false
        @unknown default:
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
