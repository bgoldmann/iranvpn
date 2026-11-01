import Foundation

/// Downloads `server-list.json` through the tunnel SOCKS port and keeps the last good copy.
enum ServerListClient {
    static let sources = [
        "https://iranvpn-config.goldmannllc.com/server-list.json",
        "https://raw.githubusercontent.com/bgoldmann/iranvpn/main/dist-config/server-list.json",
        "https://cdn.jsdelivr.net/gh/bgoldmann/iranvpn@main/dist-config/server-list.json",
    ]

    static func refresh(socksPort: Int) async {
        guard socksPort > 0 else { return }
        for url in sources {
            guard let data = await TunnelConnectivityProbe.fetch(socksPort: socksPort, urlString: url),
                  let normalized = normalize(data) else { continue }
            save(normalized)
            return
        }
    }

    static func cachedPsiphonServerListURL() -> String? {
        guard let root = load() else { return nil }
        return psiphonServerListURL(in: root)
    }

    private static func cacheURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("last_good_server_list.json")
    }

    private static func save(_ data: Data) {
        let url = cacheURL()
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: url, options: .atomic)
    }

    private static func load() -> [String: Any]? {
        guard let data = try? Data(contentsOf: cacheURL()) else { return nil }
        return normalizedObject(data)
    }

    static func normalize(_ data: Data) -> Data? {
        guard let obj = normalizedObject(data) else { return nil }
        return try? JSONSerialization.data(withJSONObject: obj)
    }

    static func normalizedObject(_ data: Data) -> [String: Any]? {
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
