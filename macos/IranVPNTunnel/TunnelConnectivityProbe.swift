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
                        "Accept-Encoding: identity",
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

    /// Status line only. A short read of `HTTP/1.1 20` must not be treated as code 20
    /// (that false-fails `generate_204`, whose real code is 204).
    private static func httpStatus(_ text: String) -> Int? {
        guard let lineEnd = text.firstIndex(of: "\n") else { return nil }
        let line = text[..<lineEnd].trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = line.split(separator: " ")
        guard parts.count >= 2, parts[0].hasPrefix("HTTP/"), parts[1].count == 3 else { return nil }
        return Int(parts[1])
    }

    /// GET through local SOCKS5. Follows up to two HTTPS redirects.
    /// Returns the response body of the final HTTP 2xx.
    static func fetch(socksPort: Int, urlString: String) async -> Data? {
        var current = urlString
        for _ in 0..<3 {
            guard let url = URL(string: current),
                  url.scheme == "https",
                  let host = url.host,
                  let port = NWEndpoint.Port(rawValue: UInt16(socksPort)) else { return nil }
            var path = url.path.isEmpty ? "/" : url.path
            if let query = url.query, !query.isEmpty {
                path += "?\(query)"
            }
            let target = Target(host: host, path: path, token: "", expectedStatus: nil, timeout: 12)
            switch await fetchOnce(socksPort: port, target: target) {
            case .body(let data):
                return data
            case .redirect(let location):
                if location.hasPrefix("https://") {
                    current = location
                } else if location.hasPrefix("/") {
                    current = "https://\(host)\(location)"
                } else {
                    return nil
                }
            case .failed:
                return nil
            }
        }
        return nil
    }

    private enum FetchOutcome {
        case body(Data)
        case redirect(String)
        case failed
    }

    private static func fetchOnce(socksPort: NWEndpoint.Port, target: Target) async -> FetchOutcome {
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
        let privacy = NWParameters.PrivacyContext(description: "IranVPN config fetch")
        privacy.proxyConfigurations = [
            ProxyConfiguration(socksv5Proxy: .hostPort(host: .ipv4(.loopback), port: socksPort))
        ]
        parameters.setPrivacyContext(privacy)
        let connection = NWConnection(host: NWEndpoint.Host(target.host), port: 443, using: parameters)
        return await withCheckedContinuation { continuation in
            let once = Once()
            func finish(_ outcome: FetchOutcome) {
                guard once.claim() else { return }
                connection.cancel()
                continuation.resume(returning: outcome)
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let request = [
                        "GET \(target.path) HTTP/1.1",
                        "Host: \(target.host)",
                        "User-Agent: IranVPN/1.0",
                        "Accept: application/json",
                        "Accept-Encoding: identity",
                        "Connection: close",
                        "",
                        "",
                    ].joined(separator: "\r\n")
                    connection.send(content: Data(request.utf8), completion: .contentProcessed { error in
                        if error != nil {
                            finish(.failed)
                            return
                        }
                        receiveFetch(connection: connection, buffer: Data(), finish: finish)
                    })
                case .failed, .cancelled:
                    finish(.failed)
                default:
                    break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + target.timeout) {
                finish(.failed)
            }
        }
    }

    private static func receiveFetch(
        connection: NWConnection,
        buffer: Data,
        finish: @escaping (FetchOutcome) -> Void
    ) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { data, _, isComplete, error in
            var next = buffer
            if let data { next.append(data) }
            let complete = isComplete || error != nil
            switch interpretFetch(buffer: next, complete: complete) {
            case .needMore:
                if complete || next.count > 1_000_000 {
                    finish(.failed)
                } else {
                    receiveFetch(connection: connection, buffer: next, finish: finish)
                }
            case .body(let body):
                finish(.body(body))
            case .redirect(let location):
                finish(.redirect(location))
            case .failed:
                finish(.failed)
            }
        }
    }

    private enum FetchParse {
        case needMore
        case body(Data)
        case redirect(String)
        case failed
    }

    private static func interpretFetch(buffer: Data, complete: Bool) -> FetchParse {
        guard let text = String(data: buffer, encoding: .isoLatin1) else {
            return complete ? .failed : .needMore
        }
        guard let status = httpStatus(text) else {
            return complete ? .failed : .needMore
        }
        let sep = Data([13, 10, 13, 10])
        guard let range = buffer.range(of: sep) else {
            return complete ? .failed : .needMore
        }
        let header = String(data: buffer[..<range.lowerBound], encoding: .isoLatin1) ?? ""
        if [301, 302, 303, 307, 308].contains(status), let location = headerValue("location", header) {
            return .redirect(location)
        }
        guard (200 ... 299).contains(status) else { return .failed }
        let raw = Data(buffer[range.upperBound...])
        if header.lowercased().contains("transfer-encoding: chunked") {
            if let decoded = decodeChunks(raw) {
                return .body(decoded)
            }
            return complete ? .failed : .needMore
        }
        if let length = contentLength(header) {
            if raw.count >= length { return .body(Data(raw.prefix(length))) }
            return complete ? .failed : .needMore
        }
        return complete ? .body(raw) : .needMore
    }

    private static func headerValue(_ name: String, _ header: String) -> String? {
        for line in header.split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            if parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == name {
                return parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    private static func contentLength(_ header: String) -> Int? {
        guard let value = headerValue("content-length", header) else { return nil }
        return Int(value)
    }

    /// nil means the chunk stream is incomplete or invalid.
    private static func decodeChunks(_ data: Data) -> Data? {
        var index = data.startIndex
        var out = Data()
        while index < data.endIndex {
            guard let lineEnd = data[index...].firstIndex(of: 10) else { return nil }
            let line = data[index..<lineEnd].filter { $0 != 13 }
            let hex = String(data: line, encoding: .utf8) ?? ""
            let sizeToken = hex.split(separator: ";").first.map(String.init) ?? ""
            guard let size = Int(sizeToken.trimmingCharacters(in: .whitespaces), radix: 16) else {
                return nil
            }
            var cursor = data.index(after: lineEnd)
            if size == 0 { return out }
            guard let end = data.index(cursor, offsetBy: size, limitedBy: data.endIndex) else { return nil }
            out.append(contentsOf: data[cursor..<end])
            cursor = end
            if cursor < data.endIndex, data[cursor] == 13 { cursor = data.index(after: cursor) }
            if cursor < data.endIndex, data[cursor] == 10 { cursor = data.index(after: cursor) }
            index = cursor
        }
        return nil
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
