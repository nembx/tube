import Foundation

enum BangumiMirrorDirectory {
    private static let url = URL(string: "https://bangumi.wiki/api/v1/mirrors")!

    static func fetch() async throws -> [BangumiSite] {
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try sites(from: data)
    }

    static func sites(from data: Data) throws -> [BangumiSite] {
        let directory = try JSONDecoder().decode(Directory.self, from: data)
        var seen = Set([BangumiSite.official.host])
        return directory.mirrors.compactMap { mirror in
            guard let host = validHost(mirror.base),
                let webURL = URL(string: mirror.url), webURL.scheme == "https",
                let web = webURL.host.flatMap(validHost),
                let api = mirror.host(for: "api"),
                let next = mirror.host(for: "next"),
                let image = mirror.host(for: "lain"),
                seen.insert(host).inserted
            else { return nil }

            return BangumiSite(host: host, name: mirror.name, serviceHosts: .init(api: api, next: next, image: image, web: web))
        }
    }

    private static func validHost(_ raw: String) -> String? {
        let host = raw.lowercased()
        let pattern = #"\A(?=.{1,253}\z)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\z"#
        return host.range(of: pattern, options: .regularExpression) == nil ? nil : host
    }

    private struct Directory: Decodable {
        let mirrors: [Mirror]
    }

    private struct Mirror: Decodable {
        let name: String
        let url: String
        let base: String
        let services: [Service]

        func host(for serviceID: String) -> String? {
            services.first { $0.id == serviceID }?.hosts.lazy.compactMap(BangumiMirrorDirectory.validHost).first
        }
    }

    private struct Service: Decodable {
        let id: String
        let hosts: [String]
    }
}
