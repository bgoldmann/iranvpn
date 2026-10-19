import Foundation

/// Port of Android ShareLinkParser — VLESS / VMess / Trojan → Xray JSON with local SOCKS inbound.
enum ShareLinkParser {
    static let defaultSocksPort = 10808

    static func toXrayJson(_ shareLink: String, socksPort: Int = defaultSocksPort) -> String? {
        let link = shareLink.trimmingCharacters(in: .whitespacesAndNewlines)
        if link.hasPrefix("vless://") { return vlessToJson(link, socksPort: socksPort) }
        if link.hasPrefix("vmess://") { return vmessToJson(link, socksPort: socksPort) }
        if link.hasPrefix("trojan://") { return trojanToJson(link, socksPort: socksPort) }
        if link.first == "{" { return ensureSocksInbound(link, port: socksPort) }
        return nil
    }

    private static func vlessToJson(_ link: String, socksPort: Int) -> String? {
        guard let parsed = parseUserAtHost(link, scheme: "vless://") else { return nil }
        let security = parsed.query["security"] ?? "none"
        let network = parsed.query["type"] ?? "tcp"
        var stream: [String: Any] = ["network": network]
        switch security {
        case "reality":
            stream["security"] = "reality"
            stream["realitySettings"] = [
                "serverName": parsed.query["sni"] ?? parsed.query["serverName"] ?? parsed.host,
                "fingerprint": parsed.query["fp"] ?? "chrome",
                "publicKey": parsed.query["pbk"] ?? "",
                "shortId": parsed.query["sid"] ?? "",
                "spiderX": parsed.query["spx"] ?? "",
            ]
        case "tls":
            stream["security"] = "tls"
            stream["tlsSettings"] = [
                "serverName": parsed.query["sni"] ?? parsed.host,
                "fingerprint": parsed.query["fp"] ?? "chrome",
                "allowInsecure": parsed.query["allowInsecure"] == "1",
            ]
        default:
            break
        }
        switch network {
        case "ws":
            stream["wsSettings"] = [
                "path": parsed.query["path"] ?? "/",
                "headers": ["Host": parsed.query["host"] ?? parsed.host],
            ]
        case "grpc":
            stream["grpcSettings"] = [
                "serviceName": parsed.query["serviceName"] ?? parsed.query["path"] ?? "",
            ]
        case "xhttp", "httpupgrade":
            stream["xhttpSettings"] = ["path": parsed.query["path"] ?? "/"]
        default:
            break
        }
        let outbound: [String: Any] = [
            "protocol": "vless",
            "settings": [
                "vnext": [[
                    "address": parsed.host,
                    "port": parsed.port,
                    "users": [[
                        "id": parsed.user,
                        "encryption": parsed.query["encryption"] ?? "none",
                        "flow": parsed.query["flow"] ?? "",
                    ]],
                ]],
            ],
            "streamSettings": stream,
        ]
        return buildFullConfig(socksPort: socksPort, outbound: outbound)
    }

    private static func vmessToJson(_ link: String, socksPort: Int) -> String? {
        let raw = String(link.dropFirst("vmess://".count))
        guard let data = Data(base64Encoded: raw) ?? Data(base64Encoded: raw.paddingBase64),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let host = obj["add"] as? String,
              let port = (obj["port"] as? Int) ?? Int("\(obj["port"] ?? "")"),
              let uuid = obj["id"] as? String
        else { return nil }
        let network = (obj["net"] as? String) ?? "tcp"
        var stream: [String: Any] = ["network": network]
        if (obj["tls"] as? String) == "tls" {
            stream["security"] = "tls"
            stream["tlsSettings"] = ["serverName": (obj["sni"] as? String) ?? host]
        }
        if network == "ws" {
            stream["wsSettings"] = [
                "path": (obj["path"] as? String) ?? "/",
                "headers": ["Host": (obj["host"] as? String) ?? host],
            ]
        }
        let outbound: [String: Any] = [
            "protocol": "vmess",
            "settings": [
                "vnext": [[
                    "address": host,
                    "port": port,
                    "users": [["id": uuid, "alterId": obj["aid"] ?? 0, "security": obj["scy"] ?? "auto"]],
                ]],
            ],
            "streamSettings": stream,
        ]
        return buildFullConfig(socksPort: socksPort, outbound: outbound)
    }

    private static func trojanToJson(_ link: String, socksPort: Int) -> String? {
        guard let parsed = parseUserAtHost(link, scheme: "trojan://") else { return nil }
        var stream: [String: Any] = ["network": parsed.query["type"] ?? "tcp", "security": "tls"]
        stream["tlsSettings"] = [
            "serverName": parsed.query["sni"] ?? parsed.host,
            "allowInsecure": parsed.query["allowInsecure"] == "1",
        ]
        let outbound: [String: Any] = [
            "protocol": "trojan",
            "settings": [
                "servers": [[
                    "address": parsed.host,
                    "port": parsed.port,
                    "password": parsed.user,
                ]],
            ],
            "streamSettings": stream,
        ]
        return buildFullConfig(socksPort: socksPort, outbound: outbound)
    }

    private static func buildFullConfig(socksPort: Int, outbound: [String: Any]) -> String? {
        let root: [String: Any] = [
            "log": ["loglevel": "warning"],
            "inbounds": [[
                "tag": "socks-in",
                "listen": "127.0.0.1",
                "port": socksPort,
                "protocol": "socks",
                "settings": ["udp": true],
            ]],
            "outbounds": [outbound, ["protocol": "freedom", "tag": "direct"]],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: root, options: []) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func ensureSocksInbound(_ json: String, port: Int) -> String? {
        guard let data = json.data(using: .utf8),
              var root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        var inbounds = (root["inbounds"] as? [[String: Any]]) ?? []
        var found = false
        for i in inbounds.indices where (inbounds[i]["protocol"] as? String) == "socks" {
            inbounds[i]["port"] = port
            inbounds[i]["listen"] = "127.0.0.1"
            found = true
        }
        if !found {
            inbounds.append([
                "tag": "socks-in",
                "listen": "127.0.0.1",
                "port": port,
                "protocol": "socks",
                "settings": ["udp": true],
            ])
        }
        root["inbounds"] = inbounds
        guard let out = try? JSONSerialization.data(withJSONObject: root) else { return nil }
        return String(data: out, encoding: .utf8)
    }

    private struct Parsed {
        var user: String
        var host: String
        var port: Int
        var query: [String: String]
    }

    private static func parseUserAtHost(_ link: String, scheme: String) -> Parsed? {
        let withoutScheme = String(link.dropFirst(scheme.count))
        let main = withoutScheme.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? withoutScheme
        guard let at = main.firstIndex(of: "@") else { return nil }
        let user = String(main[..<at]).removingPercentEncoding ?? String(main[..<at])
        let rest = String(main[main.index(after: at)...])
        let hostPortPart: String
        let queryString: String
        if let q = rest.firstIndex(of: "?") {
            hostPortPart = String(rest[..<q])
            queryString = String(rest[rest.index(after: q)...])
        } else {
            hostPortPart = rest
            queryString = ""
        }
        let host: String
        let port: Int
        if hostPortPart.hasPrefix("["), let end = hostPortPart.firstIndex(of: "]") {
            host = String(hostPortPart[hostPortPart.index(after: hostPortPart.startIndex)..<end])
            let after = hostPortPart[hostPortPart.index(after: end)...]
            port = after.hasPrefix(":") ? Int(after.dropFirst()) ?? 443 : 443
        } else if let colon = hostPortPart.lastIndex(of: ":"),
                  let p = Int(hostPortPart[hostPortPart.index(after: colon)...]) {
            host = String(hostPortPart[..<colon])
            port = p
        } else {
            host = hostPortPart
            port = 443
        }
        return Parsed(user: user, host: host, port: port, query: parseQuery(queryString))
    }

    private static func parseQuery(_ q: String) -> [String: String] {
        var out: [String: String] = [:]
        for pair in q.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard let key = parts.first else { continue }
            let value = parts.count > 1 ? (parts[1].removingPercentEncoding ?? parts[1]) : ""
            out[key] = value
        }
        return out
    }
}

private extension String {
    var paddingBase64: String {
        let pad = (4 - (count % 4)) % 4
        return self + String(repeating: "=", count: pad)
    }
}
