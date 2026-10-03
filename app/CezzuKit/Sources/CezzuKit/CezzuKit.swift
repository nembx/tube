import Foundation

/// CezzuKit 是 Cezzu App 的核心 framework，包含规则引擎、视频嗅探、播放、UI 等
/// 全部跨平台逻辑。所有平台特定的代码都收口在 App target 入口（`CezzuApp.swift`）。
public enum CezzuKit {
    /// 当前 CezzuKit 的版本号。
    public static let version = "0.1.0"
}

extension Bundle {
    /// Public re-export of `Bundle.module` so external types (e.g. App targets) can read
    /// resources bundled with `CezzuKit`. SwiftPM generates `Bundle.module` as `internal`,
    /// which breaks default-argument use from public APIs — this wrapper sidesteps that.
    public static var cezzuKit: Bundle { .module }
}
