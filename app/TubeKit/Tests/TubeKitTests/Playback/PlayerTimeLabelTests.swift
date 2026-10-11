import Foundation
import Testing
@testable import TubeKit

@Suite("PlayerTimeLabel")
struct PlayerTimeLabelTests {

    @Test("常规时长下两边各算各的")
    func formatsKnownDuration() {
        #expect(PlayerTimeLabel.elapsed(position: 42, duration: 1440) == "00:42")
        #expect(PlayerTimeLabel.total(1440) == "24:00")
        #expect(PlayerTimeLabel.remaining(position: 42, duration: 1440) == "-23:18")
    }

    @Test("超过一小时才补出小时那一段")
    func formatsHours() {
        #expect(PlayerTimeLabel.format(3661) == "1:01:01")
        #expect(PlayerTimeLabel.format(59) == "00:59")
    }

    @Test("时长还没报上来时两边一起换成占位")
    func placeholderWhenDurationUnknown() {
        for duration in [0, .infinity, TimeInterval.nan] {
            #expect(!PlayerTimeLabel.hasKnownDuration(duration))
            #expect(PlayerTimeLabel.elapsed(position: 0, duration: duration) == PlayerTimeLabel.placeholder)
            #expect(PlayerTimeLabel.total(duration) == PlayerTimeLabel.placeholder)
            #expect(
                PlayerTimeLabel.remaining(position: 0, duration: duration) == PlayerTimeLabel.placeholder
            )
        }
    }

    @Test("拖过末尾时剩余时间按 0 收口，不写负数")
    func remainingClampsAtZero() {
        #expect(PlayerTimeLabel.remaining(position: 1500, duration: 1440) == "-00:00")
    }

    @Test("位置本身是脏值时同样出占位")
    func remainingRejectsInvalidPosition() {
        #expect(PlayerTimeLabel.remaining(position: .nan, duration: 1440) == PlayerTimeLabel.placeholder)
    }
}
