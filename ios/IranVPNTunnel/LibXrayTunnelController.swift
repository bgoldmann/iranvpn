#if PATH_XRAY
import Foundation
import LibXray

/// LibXray CGo bridge — mutually exclusive with Psiphon (both embed a Go runtime).
enum LibXrayTunnelController {
    static let socksPort = ShareLinkParser.defaultSocksPort

    static func start(shareLink: String) throws {
        guard let fallback = ShareLinkParser.toXrayJson(shareLink, socksPort: socksPort) else {
            throw TunnelError.pathUnavailable
        }
        let xrayJson = convertShareLinksIfPossible(shareLink) ?? fallback
        let request: [String: Any] = [
            "apiVersion": 3,
            "method": "runXray",
            "payload": [
                "datDir": "",
                "configPath": "",
                "xrayJson": xrayJson,
            ],
        ]
        let response = try invoke(request)
        guard (response["success"] as? Bool) == true else {
            throw TunnelError.libXray((response["error"] as? String) ?? "runXray failed")
        }
    }

    static func stop() {
        let request: [String: Any] = [
            "apiVersion": 3,
            "method": "stopXray",
            "payload": [:] as [String: Any],
        ]
        _ = try? invoke(request)
    }

    private static func convertShareLinksIfPossible(_ shareLink: String) -> String? {
        let request: [String: Any] = [
            "apiVersion": 3,
            "method": "convertShareLinksToXrayJson",
            "payload": ["text": shareLink],
        ]
        guard let response = try? invoke(request),
              (response["success"] as? Bool) == true,
              let data = response["data"] as? [String: Any],
              let outbounds = data["outbounds"]
        else { return nil }
        let root: [String: Any] = [
            "log": ["loglevel": "warning"],
            "inbounds": [[
                "tag": "socks-in",
                "listen": "127.0.0.1",
                "port": socksPort,
                "protocol": "socks",
                "settings": ["udp": true],
            ]],
            "outbounds": outbounds,
        ]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: root),
              let s = String(data: jsonData, encoding: .utf8)
        else { return nil }
        return s
    }

    private static func invoke(_ request: [String: Any]) throws -> [String: Any] {
        let body = try JSONSerialization.data(withJSONObject: request)
        guard let utf8 = String(data: body, encoding: .utf8) else {
            throw TunnelError.libXray("encode request")
        }
        let responseJSON: String = try utf8.withCString { ptr in
            let mutable = strdup(ptr)
            guard let mutable else { throw TunnelError.libXray("strdup") }
            defer { free(mutable) }
            guard let raw = CGoInvoke(mutable) else {
                throw TunnelError.libXray("null response")
            }
            defer { CGoFree(raw) }
            return String(cString: raw)
        }
        guard let data = responseJSON.data(using: .utf8),
              let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw TunnelError.libXray("decode response") }
        return obj
    }
}
#endif
