import Foundation

/// Same sources as core and Android. Called after the system VPN is up, so URLSession
/// already goes through the tunnel.
enum ServerListClient {
    private static let cacheKey = "lastGoodServerListJSON"

    static let sources = [
        "https://iranvpn-config.goldmannllc.com/server-list.json",
        "https://raw.githubusercontent.com/bgoldmann/iranvpn/main/dist-config/server-list.json",
        "https://cdn.jsdelivr.net/gh/bgoldmann/iranvpn@main/dist-config/server-list.json",
    ]

    static func refresh() async {
        for urlString in sources {
            guard let url = URL(string: urlString) else { continue }
            var request = URLRequest(url: url, timeoutInterval: 12)
            request.setValue("IranVPN/1.0", forHTTPHeaderField: "User-Agent")
            request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode),
                      let normalized = normalize(data) else { continue }
                UserDefaults.standard.set(normalized, forKey: cacheKey)
                return
            } catch {
                continue
            }
        }
    }

    static func cachedPsiphonServerListURL() -> String? {
        guard let root = load() else { return nil }
        return psiphonServerListURL(in: root)
    }

    /// Share link from a published xray path, when the user has not imported one.
    static func cachedXrayShareLink() -> String? {
        guard let root = load(), let paths = root["paths"] as? [[String: Any]] else { return nil }
        for path in paths where path["type"] as? String == "xray" {
            guard let raw = path["config_json"] as? String,
                  let data = raw.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let link = obj["share_link"] as? String else { continue }
            let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }

    private static func load() -> [String: Any]? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return nil }
        return normalizedObject(data)
    }

    private static func normalize(_ data: Data) -> Data? {
        guard let obj = normalizedObject(data) else { return nil }
        return try? JSONSerialization.data(withJSONObject: obj)
    }

    private static func normalizedObject(_ data: Data) -> [String: Any]? {
        guard let any = try? JSONSerialization.jsonObject(with: data) else { return nil }
        let root: [String: Any]
        if let obj = any as? [String: Any],
           let payload = obj["payload"] as? [String: Any],
           payload["paths"] != nil
        {
            root = payload
        } else if let obj = any as? [String: Any] {
            root = obj
        } else {
            return nil
        }
        guard let paths = root["paths"] as? [[String: Any]], !paths.isEmpty else { return nil }
        guard paths.allSatisfy({ ($0["type"] as? String)?.isEmpty == false }) else { return nil }
        return root
    }

    private static func psiphonServerListURL(in root: [String: Any]) -> String? {
        guard let paths = root["paths"] as? [[String: Any]] else { return nil }
        for path in paths where path["type"] as? String == "psiphon" {
            if let url = path["server_list_url"] as? String {
                let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }
}
