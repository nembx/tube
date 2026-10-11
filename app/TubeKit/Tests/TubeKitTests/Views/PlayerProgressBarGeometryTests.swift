import Foundation
import Testing
@testable import TubeKit

@Suite("PlayerProgressBarGeometry")
struct PlayerProgressBarGeometryTests {

    @Test("fraction maps position onto 0...1")
    func fractionBasics() {
        #expect(PlayerProgressBarGeometry.fraction(position: 0, duration: 100) == 0)
        #expect(PlayerProgressBarGeometry.fraction(position: 25, duration: 100) == 0.25)
        #expect(PlayerProgressBarGeometry.fraction(position: 100, duration: 100) == 1)
    }

    @Test("fraction clamps out-of-range and invalid input")
    func fractionEdgeCases() {
        #expect(PlayerProgressBarGeometry.fraction(position: -5, duration: 100) == 0)
        #expect(PlayerProgressBarGeometry.fraction(position: 500, duration: 100) == 1)
        // 直播 / 时长未就绪时 duration 为 0 或 NaN，不能除爆。
        #expect(PlayerProgressBarGeometry.fraction(position: 10, duration: 0) == 0)
        #expect(PlayerProgressBarGeometry.fraction(position: 10, duration: .nan) == 0)
        #expect(PlayerProgressBarGeometry.fraction(position: .nan, duration: 100) == 0)
    }

    @Test("drag x maps back to time")
    func positionFromX() {
        #expect(PlayerProgressBarGeometry.position(atX: 0, width: 200, duration: 60) == 0)
        #expect(PlayerProgressBarGeometry.position(atX: 100, width: 200, duration: 60) == 30)
        #expect(PlayerProgressBarGeometry.position(atX: 200, width: 200, duration: 60) == 60)
    }

    @Test("drag beyond the track clamps instead of seeking past the ends")
    func positionFromXEdgeCases() {
        #expect(PlayerProgressBarGeometry.position(atX: -40, width: 200, duration: 60) == 0)
        #expect(PlayerProgressBarGeometry.position(atX: 999, width: 200, duration: 60) == 60)
        #expect(PlayerProgressBarGeometry.position(atX: 100, width: 0, duration: 60) == 0)
        #expect(PlayerProgressBarGeometry.position(atX: 100, width: 200, duration: 0) == 0)
    }

    @Test("thumb keeps half its width inside the track at both ends")
    func thumbCenter() {
        #expect(PlayerProgressBarGeometry.thumbCenterX(fraction: 0, width: 200, thumbWidth: 6) == 3)
        #expect(PlayerProgressBarGeometry.thumbCenterX(fraction: 1, width: 200, thumbWidth: 6) == 197)
        #expect(PlayerProgressBarGeometry.thumbCenterX(fraction: 0.5, width: 200, thumbWidth: 6) == 100)
    }

    @Test("degenerate width falls back to the middle")
    func thumbCenterDegenerateWidth() {
        #expect(PlayerProgressBarGeometry.thumbCenterX(fraction: 0.5, width: 4, thumbWidth: 6) == 2)
    }

    @Test("preview follows the thumb in the middle of the track")
    func previewFollowsThumb() {
        let x = PlayerProgressBarGeometry.previewCenterX(
            thumbCenterX: 300,
            width: 600,
            previewWidth: 168
        )

        #expect(x == 300)
    }

    @Test("preview is clamped so it never overflows either end")
    func previewClampsAtEnds() {
        #expect(
            PlayerProgressBarGeometry.previewCenterX(
                thumbCenterX: 3,
                width: 600,
                previewWidth: 168
            ) == 84
        )
        #expect(
            PlayerProgressBarGeometry.previewCenterX(
                thumbCenterX: 597,
                width: 600,
                previewWidth: 168
            ) == 516
        )
    }

    @Test("a track narrower than the preview centers it")
    func previewOnNarrowTrack() {
        #expect(
            PlayerProgressBarGeometry.previewCenterX(
                thumbCenterX: 10,
                width: 100,
                previewWidth: 168
            ) == 50
        )
    }

    // MARK: - 跑马灯

    @Test("跑马灯高亮段占轨道三分之一，短轨道上兜底 40pt")
    func marqueeSegmentWidth() {
        #expect(PlayerProgressBarGeometry.marqueeSegmentWidth(trackWidth: 300) == 100)
        #expect(PlayerProgressBarGeometry.marqueeSegmentWidth(trackWidth: 60) == 40)
        #expect(PlayerProgressBarGeometry.marqueeSegmentWidth(trackWidth: 0) == 40)
    }

    @Test("跑马灯从轨道左外侧滑到右外侧")
    func marqueeOffsetSpansTrack() {
        let width: CGFloat = 300
        let segment: CGFloat = 100

        #expect(
            PlayerProgressBarGeometry.marqueeOffsetX(phase: 0, trackWidth: width, segmentWidth: segment)
                == -segment
        )
        #expect(
            PlayerProgressBarGeometry.marqueeOffsetX(phase: 1, trackWidth: width, segmentWidth: segment)
                == width
        )
        #expect(
            PlayerProgressBarGeometry.marqueeOffsetX(phase: 0.5, trackWidth: width, segmentWidth: segment)
                == 100
        )
    }

    @Test("跑马灯进度越界时夹紧，不会把高亮甩出轨道")
    func marqueeOffsetClampsPhase() {
        let width: CGFloat = 200
        let segment: CGFloat = 80

        #expect(
            PlayerProgressBarGeometry.marqueeOffsetX(phase: -3, trackWidth: width, segmentWidth: segment)
                == -segment
        )
        #expect(
            PlayerProgressBarGeometry.marqueeOffsetX(phase: 4, trackWidth: width, segmentWidth: segment)
                == width
        )
    }

    @Test("跑马灯按挂钟走满一圈就回到起点")
    func marqueePhaseWrapsEachPeriod() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let period = PlayerProgressBarGeometry.marqueePeriod

        #expect(PlayerProgressBarGeometry.marqueePhase(at: start) == 0)
        #expect(
            abs(PlayerProgressBarGeometry.marqueePhase(at: start.addingTimeInterval(period / 2)) - 0.5)
                < 0.0001
        )
        #expect(
            abs(PlayerProgressBarGeometry.marqueePhase(at: start.addingTimeInterval(period))) < 0.0001
        )
    }
}
