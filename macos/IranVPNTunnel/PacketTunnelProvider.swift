import NetworkExtension
import os.log

/// macOS NEPacketTunnelProvider — Psiphon path + PAC SOCKS (parity with iOS).
/// Build with `PATH_PSIPHON` and link `../ios/Vendor/PsiphonTunnel.xcframework` (macos slice).
class PacketTunnelProvider: NEPacketTunnelProvider {
    private let log = OSLog(subsystem: "com.goldmannllc.IranVPN", category: "PacketTunnel")
    private var isRunning = false
    private var socksPort: Int = 0
#if PATH_PSIPHON
    private var psiphon: PsiphonTunnelController?
#endif

    override func startTunnel(options: [String: NSObject]?) async throws {
        os_log("Starting Iran VPN tunnel (macOS)", log: log, type: .info)
        isRunning = true

        let proto = protocolConfiguration as? NETunnelProviderProtocol
        let shareLink = proto?.providerConfiguration?["share_link"] as? String
        let configuredPort = proto?.providerConfiguration?["socks_port"] as? Int

        if let port = configuredPort, port > 0 {
            socksPort = port
        } else if let port = try await startEmbeddedPath(shareLink: shareLink) {
            socksPort = port
        } else {
            throw TunnelError.pathUnavailable
        }

        guard await probeSocksReady(port: socksPort) else {
            throw TunnelError.probeFailed
        }

        try await setTunnelNetworkSettings(SocksNetworkSettings.make(socksPort: socksPort))
        readPackets()
    }

    private func startEmbeddedPath(shareLink: String?) async throws -> Int? {
#if PATH_PSIPHON
        _ = shareLink
        let controller = PsiphonTunnelController()
        psiphon = controller
        return try await controller.start()
#else
        _ = shareLink
        return nil
#endif
    }

    private func probeSocksReady(port: Int) async -> Bool {
        await withCheckedContinuation { cont in
            DispatchQueue.global().async {
                let sock = CFSocketCreate(
                    kCFAllocatorDefault, PF_INET, SOCK_STREAM, IPPROTO_TCP, 0, nil, nil
                )
                defer { if let sock { CFSocketInvalidate(sock) } }
                guard sock != nil else {
                    cont.resume(returning: false)
                    return
                }
                var addr = sockaddr_in()
                addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
                addr.sin_family = sa_family_t(AF_INET)
                addr.sin_port = in_port_t(UInt16(port)).bigEndian
                addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
                let data = withUnsafePointer(to: &addr) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                        NSData(bytes: sa, length: MemoryLayout<sockaddr_in>.size)
                    }
                }
                let err = CFSocketConnectToAddress(sock, data as CFData, 3.0)
                cont.resume(returning: err == .success)
            }
        }
    }

    private func readPackets() {
        guard isRunning else { return }
        packetFlow.readPackets { [weak self] packets, protocols in
            guard let self, self.isRunning else { return }
            // PAC SOCKS handles TCP; drain the flow without leaking cleartext.
            _ = packets
            _ = protocols
            self.readPackets()
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason) async {
        isRunning = false
        socksPort = 0
#if PATH_PSIPHON
        psiphon?.stop()
        psiphon = nil
#endif
        os_log("Stopping: %{public}@", log: log, type: .info, String(describing: reason))
    }
}
