import NetworkExtension

enum SocksNetworkSettings {
    /// IPv4/IPv6/DNS + PAC that points TCP at the local SOCKS listener.
    static func make(socksPort: Int, mtu: Int = 1280) -> NEPacketTunnelNetworkSettings {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "10.0.0.1")
        settings.mtu = NSNumber(value: mtu)

        let ipv4 = NEIPv4Settings(addresses: ["10.0.0.2"], subnetMasks: ["255.255.255.0"])
        ipv4.includedRoutes = [NEIPv4Route.default()]
        settings.ipv4Settings = ipv4

        let ipv6 = NEIPv6Settings(addresses: ["fd00::2"], networkPrefixLengths: [64])
        ipv6.includedRoutes = [NEIPv6Route.default()]
        settings.ipv6Settings = ipv6

        settings.dnsSettings = NEDNSSettings(servers: ["198.18.0.2"])
        settings.dnsSettings?.matchDomains = [""]

        let proxy = NEProxySettings()
        proxy.autoProxyConfigurationEnabled = true
        proxy.proxyAutoConfigurationJavaScript = """
        function FindProxyForURL(url, host) {
            if (isPlainHostName(host) || host === "127.0.0.1" || host === "::1") {
                return "DIRECT";
            }
            return "SOCKS5 127.0.0.1:\(socksPort); SOCKS 127.0.0.1:\(socksPort)";
        }
        """
        proxy.matchDomains = [""]
        proxy.excludeSimpleHostnames = true
        settings.proxySettings = proxy

        return settings
    }
}
