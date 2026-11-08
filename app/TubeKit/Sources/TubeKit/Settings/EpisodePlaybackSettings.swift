import Foundation

struct EpisodePlaybackSettings: Codable, Equatable, Sendable {
    var openingSeconds: Double = 0
    var endingSeconds: Double = 0
    var autoPlayNext: Bool = false

    var sanitized: Self {
        var settings = self
        settings.openingSeconds = openingSeconds.isFinite ? min(max(openingSeconds, 0), 600) : 0
        settings.endingSeconds = endingSeconds.isFinite ? min(max(endingSeconds, 0), 600) : 0
        return settings
    }
}

enum EpisodePlaybackSettingsStore {
    static func identity(for request: PlaybackRequest) -> String {
        HistoryStore.identityKey(
            title: HistoryStore.bangumiTitle(for: request),
            detailURL: request.anime.detailURL.absoluteString
        )
    }

    static func load(identity: String, defaults: UserDefaults = .standard) -> EpisodePlaybackSettings {
        guard let data = defaults.data(forKey: key(identity)),
              let settings = try? JSONDecoder().decode(EpisodePlaybackSettings.self, from: data)
        else { return EpisodePlaybackSettings() }
        return settings.sanitized
    }

    static func save(_ settings: EpisodePlaybackSettings, identity: String, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(settings.sanitized) else { return }
        defaults.set(data, forKey: key(identity))
    }

    private static func key(_ identity: String) -> String {
        "tube.playback.episodePreferences." + Data(identity.utf8).base64EncodedString()
    }
}
