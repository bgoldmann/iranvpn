import NetworkExtension
import os.log

/// NEPacketTunnelProvider for Iran VPN.
/// Build flags:
/// - `PATH_PSIPHON` (default IranVPNTunnel): links PsiphonTunnel.xcframework
/// - `PATH_XRAY` (IranVPNTunnelXray): links LibXray.xcframework
/// Never link both Go frameworks into one process.
class PacketTunnelProvider: NEPacketTunnelProvider {
    private let log = OSLog(subsystem: "com.goldmannllc.IranVPN", category: "PacketTunnel")
    private var isRunning = false
    private var socksPort: Int = 0
#if PATH_PSIPHON
    private var psiphon: PsiphonTunnelController?
#endif

    override func startTunnel(options: [String: NSObject]?) async throws {
        os_log("Starting Iran VPN tunnel", log: log, type: .info)
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
        startPacketLoop()
    }

    private func startEmbeddedPath(shareLink: String?) async throws -> Int? {
#if PATH_XRAY
        guard let link = shareLink, !link.isEmpty else {
            throw TunnelError.pathUnavailable
        }
        try LibXrayTunnelController.start(shareLink: link)
        // Brief settle for SOCKS bind
        try await Task.sleep(for: .milliseconds(400))
        return LibXrayTunnelController.socksPort
#elseif PATH_PSIPHON
        _ = shareLink
        let controller = PsiphonTunnelController()
        psiphon = controller
        let port = try await controller.start()
        return port
#else
        _ = shareLink
        // Deps not fetched / flags not set — fail clearly
        return nil
#endif
    }

    private func probeSocksReady(port: Int) async -> Bool {
        await withCheckedContinuation { cont in
            DispatchQueue.global().async {
                let sock = CFSocketCreate(
                    kCFAllocatorDefault,
                    PF_INET,
                    SOCK_STREAM,
                    IPPROTO_TCP,
                    0,
                    nil,
                    nil
                )
                defer {
                    if let sock {
                        CFSocketInvalidate(sock)
                    }
                }
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

    private func startPacketLoop() {
        // With SOCKS proxySettings installed, the system forwards TCP to the local proxy.
        // Keep reading to drain the flow; do not leak cleartext to the ISP.
        readPackets()
    }

    private func readPackets() {
        guard isRunning else { return }
        packetFlow.readPackets { [weak self] packets, protocols in
            guard let self, self.isRunning else { return }
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
#if PATH_XRAY
        LibXrayTunnelController.stop()
#endif
        os_log("Stopping tunnel: %{public}@", log: log, type: .info, String(describing: reason))
    }
}
