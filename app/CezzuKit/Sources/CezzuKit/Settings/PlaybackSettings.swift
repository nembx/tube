import Foundation
import SwiftUI

/// 播放器相关的用户设置。
public enum PlaybackSettings {
    public static let enableLocalProxyKey = "cezzu.playback.enableLocalProxy"
    public static let enableDanmakuKey = "cezzu.playback.enableDanmaku"
    public static let danmakuFontSizeKey = "cezzu.playback.danmakuFontSize"
    public static let danmakuOpacityKey = "cezzu.playback.danmakuOpacity"
    public static let danmakuAreaKey = "cezzu.playback.danmakuArea"
    public static let danmakuDurationKey = "cezzu.playback.danmakuDuration"
    public static let danmakuLineHeightKey = "cezzu.playback.danmakuLineHeight"
    public static let showTopDanmakuKey = "cezzu.playback.showTopDanmaku"
    public static let showBottomDanmakuKey = "cezzu.playback.showBottomDanmaku"
    public static let showScrollDanmakuKey = "cezzu.playback.showScrollDanmaku"
    public static let followPlaybackRateDanmakuKey = "cezzu.playback.followPlaybackRateDanmaku"
    public static let superResolutionModeKey = "cezzu.playback.superResolutionMode"

    /// 默认值。
    public static let enableLocalProxyDefault = true
    public static let superResolutionModeDefault: SuperResolutionMode = .off
    public static let enableDanmakuDefault = true
    public static let danmakuFontSizeDefault = 22.0
    public static let danmakuOpacityDefault = 1.0
    public static let danmakuAreaDefault = 0.75
    public static let danmakuDurationDefault = 8.0
    public static let danmakuLineHeightDefault = 1.0
    public static let showTopDanmakuDefault = true
    public static let showBottomDanmakuDefault = true
    public static let showScrollDanmakuDefault = true
    public static let followPlaybackRateDanmakuDefault = true

    struct Store {
        let defaults: UserDefaults

        var enableLocalProxy: Bool {
            get {
                if defaults.object(forKey: PlaybackSettings.enableLocalProxyKey) == nil {
                    return PlaybackSettings.enableLocalProxyDefault
                }
                return defaults.bool(forKey: PlaybackSettings.enableLocalProxyKey)
            }
            set {
                defaults.set(newValue, forKey: PlaybackSettings.enableLocalProxyKey)
            }
        }

        var enableDanmaku: Bool {
            get {
                bool(forKey: PlaybackSettings.enableDanmakuKey, defaultValue: PlaybackSettings.enableDanmakuDefault)
            }
            set {
                defaults.set(newValue, forKey: PlaybackSettings.enableDanmakuKey)
            }
        }

        var danmakuFontSize: Double {
            get {
                double(forKey: PlaybackSettings.danmakuFontSizeKey, defaultValue: PlaybackSettings.danmakuFontSizeDefault)
            }
            set {
                defaults.set(newValue, forKey: PlaybackSettings.danmakuFontSizeKey)
            }
        }

        var danmakuOpacity: Double {
            get {
                double(forKey: PlaybackSettings.danmakuOpacityKey, defaultValue: PlaybackSettings.danmakuOpacityDefault)
            }
            set {
                defaults.set(newValue, forKey: PlaybackSettings.danmakuOpacityKey)
            }
        }

        var danmakuArea: Double {
            get {
                double(forKey: PlaybackSettings.danmakuAreaKey, defaultValue: PlaybackSettings.danmakuAreaDefault)
            }
            set {
                defaults.set(newValue, forKey: PlaybackSettings.danmakuAreaKey)
            }
        }

        var danmakuDuration: Double {
            get {
                double(forKey: PlaybackSettings.danmakuDurationKey, defaultValue: PlaybackSettings.danmakuDurationDefault)
            }
            set {
                defaults.set(newValue, forKey: PlaybackSettings.danmakuDurationKey)
            }
        }

        var danmakuLineHeight: Double {
            get {
                double(forKey: PlaybackSettings.danmakuLineHeightKey, defaultValue: PlaybackSettings.danmakuLineHeightDefault)
            }
            set {
                defaults.set(newValue, forKey: PlaybackSettings.danmakuLineHeightKey)
            }
        }

        var showTopDanmaku: Bool {
            get {
                bool(forKey: PlaybackSettings.showTopDanmakuKey, defaultValue: PlaybackSettings.showTopDanmakuDefault)
            }
            set {
                defaults.set(newValue, forKey: PlaybackSettings.showTopDanmakuKey)
            }
        }

        var showBottomDanmaku: Bool {
            get {
                bool(forKey: PlaybackSettings.showBottomDanmakuKey, defaultValue: PlaybackSettings.showBottomDanmakuDefault)
            }
            set {
                defaults.set(newValue, forKey: PlaybackSettings.showBottomDanmakuKey)
            }
        }

        var showScrollDanmaku: Bool {
            get {
                bool(forKey: PlaybackSettings.showScrollDanmakuKey, defaultValue: PlaybackSettings.showScrollDanmakuDefault)
            }
            set {
                defaults.set(newValue, forKey: PlaybackSettings.showScrollDanmakuKey)
            }
        }

        var followPlaybackRateDanmaku: Bool {
            get {
                bool(
                    forKey: PlaybackSettings.followPlaybackRateDanmakuKey,
                    defaultValue: PlaybackSettings.followPlaybackRateDanmakuDefault
                )
            }
            set {
                defaults.set(newValue, forKey: PlaybackSettings.followPlaybackRateDanmakuKey)
            }
        }

        var superResolutionMode: SuperResolutionMode {
            get {
                guard let raw = defaults.string(forKey: PlaybackSettings.superResolutionModeKey),
                      let mode = SuperResolutionMode(rawValue: raw)
                else {
                    return PlaybackSettings.superResolutionModeDefault
                }
                return mode
            }
            set {
                defaults.set(newValue.rawValue, forKey: PlaybackSettings.superResolutionModeKey)
            }
        }

        private func bool(forKey key: String, defaultValue: Bool) -> Bool {
            if defaults.object(forKey: key) == nil {
                return defaultValue
            }
            return defaults.bool(forKey: key)
        }

        private func double(forKey key: String, defaultValue: Double) -> Double {
            if defaults.object(forKey: key) == nil {
                return defaultValue
            }
            return defaults.double(forKey: key)
        }
    }

    /// 当前值（同步读取）。
    public static var enableLocalProxy: Bool {
        get {
            Store(defaults: .standard).enableLocalProxy
        }
        set {
            var store = Store(defaults: .standard)
            store.enableLocalProxy = newValue
        }
    }

    public static var enableDanmaku: Bool {
        get {
            Store(defaults: .standard).enableDanmaku
        }
        set {
            var store = Store(defaults: .standard)
            store.enableDanmaku = newValue
        }
    }

    public static var danmakuFontSize: Double {
        get {
            Store(defaults: .standard).danmakuFontSize
        }
        set {
            var store = Store(defaults: .standard)
            store.danmakuFontSize = newValue
        }
    }

    public static var danmakuOpacity: Double {
        get {
            Store(defaults: .standard).danmakuOpacity
        }
        set {
            var store = Store(defaults: .standard)
            store.danmakuOpacity = newValue
        }
    }

    public static var danmakuArea: Double {
        get {
            Store(defaults: .standard).danmakuArea
        }
        set {
            var store = Store(defaults: .standard)
            store.danmakuArea = newValue
        }
    }

    public static var danmakuDuration: Double {
        get {
            Store(defaults: .standard).danmakuDuration
        }
        set {
            var store = Store(defaults: .standard)
            store.danmakuDuration = newValue
        }
    }

    public static var danmakuLineHeight: Double {
        get {
            Store(defaults: .standard).danmakuLineHeight
        }
        set {
            var store = Store(defaults: .standard)
            store.danmakuLineHeight = newValue
        }
    }

    public static var showTopDanmaku: Bool {
        get {
            Store(defaults: .standard).showTopDanmaku
        }
        set {
            var store = Store(defaults: .standard)
            store.showTopDanmaku = newValue
        }
    }

    public static var showBottomDanmaku: Bool {
        get {
            Store(defaults: .standard).showBottomDanmaku
        }
        set {
            var store = Store(defaults: .standard)
            store.showBottomDanmaku = newValue
        }
    }

    public static var showScrollDanmaku: Bool {
        get {
            Store(defaults: .standard).showScrollDanmaku
        }
        set {
            var store = Store(defaults: .standard)
            store.showScrollDanmaku = newValue
        }
    }

    public static var followPlaybackRateDanmaku: Bool {
        get {
            Store(defaults: .standard).followPlaybackRateDanmaku
        }
        set {
            var store = Store(defaults: .standard)
            store.followPlaybackRateDanmaku = newValue
        }
    }

    public static var superResolutionMode: SuperResolutionMode {
        get {
            Store(defaults: .standard).superResolutionMode
        }
        set {
            var store = Store(defaults: .standard)
            store.superResolutionMode = newValue
        }
    }
}
