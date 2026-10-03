import Testing
@testable import CezzuKit

@Suite("PlayerBufferedRangeResolver")
struct PlayerBufferedRangeResolverTests {

    private func range(_ start: Double, _ end: Double) -> PlayerBufferedRangeResolver.Range {
        PlayerBufferedRangeResolver.Range(start: start, end: end)
    }

    @Test("single range returns its end")
    func singleRange() {
        let buffered = PlayerBufferedRangeResolver.bufferedTime(
            ranges: [range(0, 30)],
            currentTime: 10
        )

        #expect(buffered == 30)
    }

    @Test("seek leaves disjoint ranges, only the one holding the playhead counts")
    func disjointRanges() {
        let ranges = [range(0, 20), range(120, 180)]

        #expect(PlayerBufferedRangeResolver.bufferedTime(ranges: ranges, currentTime: 5) == 20)
        #expect(PlayerBufferedRangeResolver.bufferedTime(ranges: ranges, currentTime: 150) == 180)
    }

    @Test("playhead inside a gap has no buffered time")
    func playheadInGap() {
        let buffered = PlayerBufferedRangeResolver.bufferedTime(
            ranges: [range(0, 20), range(120, 180)],
            currentTime: 60
        )

        #expect(buffered == nil)
    }

    @Test("no ranges yields nil")
    func emptyRanges() {
        #expect(PlayerBufferedRangeResolver.bufferedTime(ranges: [], currentTime: 0) == nil)
    }

    @Test("range boundaries are inclusive")
    func inclusiveBoundaries() {
        let ranges = [range(10, 40)]

        #expect(PlayerBufferedRangeResolver.bufferedTime(ranges: ranges, currentTime: 10) == 40)
        #expect(PlayerBufferedRangeResolver.bufferedTime(ranges: ranges, currentTime: 40) == 40)
        #expect(PlayerBufferedRangeResolver.bufferedTime(ranges: ranges, currentTime: 9.9) == nil)
    }
}
