import Foundation
import Network
import Security

/// Same gate as `core/src/probe.rs` and Android `ConnectivityProbe`.
/// SOCKS5 sends the hostname (remote DNS). TLS stays end-to-end to that host.
enum TunnelConnectivityProbe {
    private struct Target {
        let host: String
        let path: String
        let token: String
        let expectedStatus: Int?
        let timeout: TimeInterval
    }

    private static let targets: [Target] = [
        Target(
            host: "www.cloudflare.com",
            path: "/cdn-cgi/trace",
            token: "ip=",
            expectedStatus: nil,
            timeout: 8
        ),
        Target(
            host: "www.gstatic.com",
            path: "/generate_204",
            token: "",
            expectedStatus: 204,
            timeout: 4
        ),
        Target(
            host: "detectportal.firefox.com",
            path: "/success.txt",
            token: "success",
            expectedStatus: nil,
            timeout: 4
        ),
    ]

    private static let queue = DispatchQueue(label: "com.goldmannllc.IranVPN.probe", qos: .utility)

    static func probe(socksPort: Int) async -> Bool {
        guard let port = NWEndpoint.Port(rawValue: UInt16(socksPort)) else { return false }
        for target in targets {
            if await probeOne(socksPort: port, target: target) {
                return true
            }
        }
        return false
    }

    private static func probeOne(socksPort: NWEndpoint.Port, target: Target) async -> Bool {
        let tls = NWProtocolTLS.Options()
        "http/1.1".withCString { protocolName in
            sec_protocol_options_add_tls_application_protocol(
                tls.securityProtocolOptions,
                protocolName
            )
        }
        let tcp = NWProtocolTCP.Options()
        tcp.connectionTimeout = Int(target.timeout.rounded(.up))
        let parameters = NWParameters(tls: tls, tcp: tcp)
        let privacy = NWParameters.PrivacyContext(description: "IranVPN probe")
        privacy.proxyConfigurations = [
            ProxyConfiguration(socksv5Proxy: .hostPort(host: .ipv4(.loopback), port: socksPort))
        ]
        parameters.setPrivacyContext(privacy)

        let connection = NWConnection(
            host: NWEndpoint.Host(target.host),
            port: 443,
            using: parameters
        )

        return await withCheckedContinuation { continuation in
            let once = Once()
            func finish(_ ok: Bool) {
                guard once.claim() else { return }
                connection.cancel()
                continuation.resume(returning: ok)
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let request = [
                        "GET \(target.path) HTTP/1.1",
                        "Host: \(target.host)",
                        "User-Agent: IranVPN/1.0",
                        "Accept: */*",
                        "Connection: close",
                        "",
                        "",
                    ].joined(separator: "\r\n")
                    connection.send(content: Data(request.utf8), completion: .contentProcessed { error in
                        if error != nil {
                            finish(false)
                            return
                        }
                        receive(connection: connection, target: target, buffer: Data(), finish: finish)
                    })
                case .failed, .cancelled:
                    finish(false)
                default:
                    break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + target.timeout) {
                finish(false)
            }
        }
    }

    private static func receive(
        connection: NWConnection,
        target: Target,
        buffer: Data,
        finish: @escaping (Bool) -> Void
    ) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { data, _, isComplete, error in
            var next = buffer
            if let data {
                next.append(data)
            }
            let complete = isComplete || error != nil
            switch evaluate(buffer: next, target: target, complete: complete) {
            case .some(let ok):
                finish(ok)
            case .none:
                if complete || next.count > 65_536 {
                    finish(false)
                } else {
                    receive(connection: connection, target: target, buffer: next, finish: finish)
                }
            }
        }
    }

    /// nil = need more bytes. false = this target failed. true = probe passed.
    private static func evaluate(buffer: Data, target: Target, complete: Bool) -> Bool? {
        guard let text = String(data: buffer, encoding: .utf8) ?? String(data: buffer, encoding: .isoLatin1) else {
            return complete ? false : nil
        }
        guard let status = httpStatus(text) else {
            return complete ? false : nil
        }
        if let expected = target.expectedStatus {
            if status != expected { return false }
        } else if !(200 ... 299).contains(status) {
            return false
        }
        if target.token.isEmpty {
            return true
        }
        guard let headerEnd = text.range(of: "\r\n\r\n") else {
            return complete ? false : nil
        }
        let body = text[headerEnd.upperBound...]
        if body.contains(target.token) { return true }
        return complete ? false : nil
    }

    private static func httpStatus(_ text: String) -> Int? {
        let lineEnd = text.firstIndex(of: "\n") ?? text.endIndex
        let line = text[..<lineEnd].trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = line.split(separator: " ")
        guard parts.count >= 2, parts[0].hasPrefix("HTTP/") else { return nil }
        return Int(parts[1])
    }

    private final class Once {
        private let lock = NSLock()
        private var done = false

        func claim() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            if done { return false }
            done = true
            return true
        }
    }
}
