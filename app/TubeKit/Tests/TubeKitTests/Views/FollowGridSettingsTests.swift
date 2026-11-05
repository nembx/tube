import Foundation
import Testing
@testable import TubeKit

@Suite("FollowGridSettings")
struct FollowGridSettingsTests {

    private func makeDefaults() -> UserDefaults {
        let suite = "FollowGridSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    /// 加开关之前窄屏就是 3 列，默认值必须是三列，否则老用户升级后版式会变。
    @Test("defaults to three columns")
    func defaultsToThree() {
        #expect(FollowGridSettings.density(from: makeDefaults()) == .three)
        #expect(FollowGridSettings.densityDefault == .three)
    }

    @Test("round-trips the stored density")
    func roundTripsStoredDensity() {
        let defaults = makeDefaults()
        defaults.set(FollowGridDensity.two.rawValue, forKey: FollowGridSettings.densityKey)
        #expect(FollowGridSettings.density(from: defaults) == .two)
    }

    @Test("an unknown stored value falls back to the default")
    func unknownValueFallsBack() {
        let defaults = makeDefaults()
        defaults.set("nine", forKey: FollowGridSettings.densityKey)
        #expect(FollowGridSettings.density(from: defaults) == .three)
    }

    /// 两档的列数要和宫格布局对得上：三列 = `compactColumnCount`，两列 = 2。
    @Test("density maps onto the grid column counts")
    func columnCountMapping() {
        #expect(FollowGridDensity.three.columnCount == BangumiGridLayout.compactColumnCount)
        #expect(FollowGridDensity.two.columnCount == 2)
    }

    /// 图标名正是需求里的 3x3 / 2x2 两个 SF Symbol。
    @Test("each density carries its grid icon")
    func systemImages() {
        #expect(FollowGridDensity.three.systemImage == "square.grid.3x3")
        #expect(FollowGridDensity.two.systemImage == "square.grid.2x2")
    }

    @Test("toggling flips between the two densities")
    func toggleFlips() {
        #expect(FollowGridDensity.three.toggled == .two)
        #expect(FollowGridDensity.two.toggled == .three)
        #expect(FollowGridDensity.three.label == "三列")
        #expect(FollowGridDensity.two.label == "两列")
    }
}
