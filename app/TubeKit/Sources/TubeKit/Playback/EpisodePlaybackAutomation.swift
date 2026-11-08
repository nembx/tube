import Foundation

struct EpisodePlaybackAutomation {
    enum Action: Equatable {
        case seek(Double)
        case nextEpisode
    }

    private(set) var countdown: Int?
    private var openingHandled = false
    private var endingHandled = false
    private var cancelled = false

    mutating func cancel() {
        cancelled = true
        countdown = nil
    }

    mutating func tick(
        time: Double,
        duration: Double,
        isPlaying: Bool,
        isBuffering: Bool,
        didEnd: Bool,
        hasNext: Bool,
        settings: EpisodePlaybackSettings
    ) -> Action? {
        guard time.isFinite, duration.isFinite, duration > 0 else { return nil }
        let settings = settings.sanitized
        let endingStart = duration - settings.endingSeconds
        let validSegments = settings.openingSeconds + settings.endingSeconds < duration

        if !openingHandled, isPlaying, !isBuffering {
            openingHandled = true
            if validSegments, settings.openingSeconds > 0, time < settings.openingSeconds {
                return .seek(settings.openingSeconds)
            }
        }

        let reachedEnding = validSegments && settings.endingSeconds > 0 && time >= endingStart
        guard !cancelled, !endingHandled else { return nil }
        guard reachedEnding || didEnd else {
            countdown = nil
            return nil
        }
        guard didEnd || (!isBuffering && isPlaying) else { return nil }

        if !settings.autoPlayNext || !hasNext {
            countdown = nil
        }

        if settings.autoPlayNext && hasNext {
            if let remaining = countdown {
                if remaining <= 1 {
                    countdown = nil
                    endingHandled = true
                    return .nextEpisode
                }
                countdown = remaining - 1
            } else {
                countdown = 5
            }
        } else {
            countdown = nil
            if reachedEnding {
                endingHandled = true
                return .seek(duration)
            }
        }
        return nil
    }
}
