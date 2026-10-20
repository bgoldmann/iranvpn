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
    @ObservationIgnored
    private let statusObserver = VpnStatusObserverBox()
    /// Skip NE APIs after permission denied (or on Simulator, where Packet Tunnel cannot run).
    @ObservationIgnored
    private var networkExtensionDenied = false
    /// Bumped on disconnect/cancel so an in-flight connect loop exits cleanly.
    @ObservationIgnored
    private var connectGeneration = 0

    /// True when the Xray Packet Tunnel appex was embedded in this build.
    var xrayExtensionAvailable: Bool {
        guard let plugins = Bundle.main.builtInPlugInsURL else { return false }
        return FileManager.default.fileExists(
            atPath: plugins.appendingPathComponent("IranVPNTunnelXray.appex").path
        )
    }

    private var preferredTunnelBundleId: String {
        if xrayExtensionAvailable, let link = importedShareLink, !link.isEmpty {
            return xrayTunnelBundleId
        }
        return psiphonTunnelBundleId
    }

    init() {
        importedShareLink = UserDefaults.standard.string(forKey: shareLinkKey)
#if targetEnvironment(simulator)
        // Packet Tunnel cannot run in Simulator — skip all NE APIs (avoids XPC / config noise).
        networkExtensionDenied = true
        errorMessage = Self.simulatorUnavailableMessage
#endif
    }

    deinit {
        statusObserver.invalidate()
    }

    func clearShareLink() {
        importedShareLink = nil
    }

    func refreshStatus() async {
        guard !networkExtensionDenied else { return }
        do {
            let managers = try await NETunnelProviderManager.loadAllFromPreferences()
            installStatusObserverIfNeeded()
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
                if let compartment = UserDefaults.standard.string(forKey: "conduitPersonalCompartment"),
                   !compartment.isEmpty
                {
                    providerConfig["InproxyClientPersonalCompartmentID"] = compartment
                } else {
                    providerConfig.removeValue(forKey: "InproxyClientPersonalCompartmentID")
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

            // Reconnect requires a fully stopped tunnel — start while .disconnecting fails silently.
            try await ensureTunnelStopped(manager)
            guard generation == connectGeneration else { return }

            try manager.connection.startVPNTunnel()
            installStatusObserverIfNeeded()
            let intendedPath =
                (xrayExtensionAvailable && importedShareLink?.isEmpty == false) ? "Xray" : "Psiphon"

            var sawActivity = false
            for i in 0..<120 {
                guard generation == connectGeneration else {
                    isConnecting = false
                    return
                }
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
            guard generation == connectGeneration else { return }
            isConnecting = false
            activePath = nil
            if !isConnected {
                errorMessage =
                    "Tunnel did not connect — run scripts/fetch-ios-tunnel-deps.sh, embed \(bundleId), and enable Network Extension signing."
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
            let bundleId = preferredTunnelBundleId
            if let manager = preferredManager(from: managers, bundleId: bundleId) {
                manager.connection.stopVPNTunnel()
                await waitUntilTunnelStopped(manager)
            } else {
                for manager in managers where isIranVPN(manager) {
                    manager.connection.stopVPNTunnel()
                }
            }
        } catch {
            handleConfigurationError(error)
        }
        isConnected = false
        isConnecting = false
        activePath = nil
    }

    /// Stop if needed, then wait until NEVPN is idle so a new startVPNTunnel can succeed.
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

    private static let networkExtensionSetupMessage =
        "VPN not available — Packet Tunnel entitlement missing. Enable it on the App IDs in the Apple Developer portal, set IRANVPN_ENTITLEMENTS_SUFFIX=-NetworkExtension in ios/Config/NetworkExtension.xcconfig, rebuild. Details: ios/README.md"

    private static let simulatorUnavailableMessage =
        "Simulator cannot run Packet Tunnel VPN. Build & run on a physical iPhone to Connect."

    private func installStatusObserverIfNeeded() {
        guard statusObserver.token == nil, !networkExtensionDenied else { return }
        statusObserver.token = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            // Apply status directly — avoid nested loadAllFromPreferences + Task hop storms.
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
            // Do not treat as "connecting" — keep Connect available after stop.
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
                await waitUntilTunnelStopped(manager)
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
