import NetworkExtension
import os.log

/// macOS NEPacketTunnelProvider — probe + kill-switch; no fake success.
class PacketTunnelProvider: NEPacketTunnelProvider {
    private let log = OSLog(subsystem: "com.goldmannllc.IranVPN", category: "PacketTunnel")
    private var isRunning = false
    private var socksPort: Int = 0

    override func startTunnel(options: [String: NSObject]?) async throws {
        os_log("Starting Iran VPN tunnel (macOS)", log: log, type: .info)
        isRunning = true

        let proto = protocolConfiguration as? NETunnelProviderProtocol
        let shareLink = (proto?.providerConfiguration?["share_link"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let configuredPort = proto?.providerConfiguration?["socks_port"] as? Int

        if let port = configuredPort, port > 0 {
            socksPort = port
        } else if let link = shareLink, !link.isEmpty {
            throw makeError("Link Psiphon or Xray into the extension (share link alone is not enough yet)")
        } else {
            throw makeError("No path — set providerConfiguration socks_port for testing, or embed a library")
        }

        guard await tcpConnectProbe(port: socksPort) else {
            throw makeError("Connectivity probe failed — SOCKS not accepting")
        }

        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "10.0.0.1")
        settings.mtu = 1280
        settings.ipv4Settings = NEIPv4Settings(addresses: ["10.0.0.2"], subnetMasks: ["255.255.255.0"])
        settings.ipv4Settings?.includedRoutes = [NEIPv4Route.default()]
        settings.dnsSettings = NEDNSSettings(servers: ["198.18.0.2"])
        settings.ipv6Settings = NEIPv6Settings(addresses: ["fd00::2"], networkPrefixLengths: [64])
        settings.ipv6Settings?.includedRoutes = [NEIPv6Route.default()]
        try await setTunnelNetworkSettings(settings)
        readPackets()
    }

    private func tcpConnectProbe(port: Int) async -> Bool {
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
                addr.sin_port = in_port_t(port).bigEndian
                addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
                let data = withUnsafePointer(to: &addr) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                        NSData(bytes: sa, length: MemoryLayout<sockaddr_in>.size) as CFData
                    }
                }
                let err = CFSocketConnectToAddress(sock, data, 3.0)
                cont.resume(returning: err == .success)
            }
        }
    }

    private func readPackets() {
        guard isRunning else { return }
        packetFlow.readPackets { [weak self] packets, protocols in
            guard let self, self.isRunning else { return }
            // Kill switch until tun2socks linked
            _ = packets
            _ = protocols
            _ = self.socksPort
            self.readPackets()
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason) async {
        isRunning = false
        socksPort = 0
        os_log("Stopping: %{public}@", log: log, type: .info, String(describing: reason))
    }

    private func makeError(_ msg: String) -> NSError {
        NSError(domain: "com.goldmannllc.IranVPN", code: 1, userInfo: [
            NSLocalizedDescriptionKey: msg
        ])
    }
}
