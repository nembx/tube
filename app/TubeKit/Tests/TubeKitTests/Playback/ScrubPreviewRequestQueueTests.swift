import Testing
@testable import TubeKit

@Suite("ScrubPreviewRequestQueue")
struct ScrubPreviewRequestQueueTests {

    @Test("the first request goes out immediately")
    func firstRequestStartsNow() {
        var queue = ScrubPreviewRequestQueue()

        #expect(queue.request(at: 30) == 30)
        #expect(queue.inFlight == 30)
    }

    @Test("requests made while one is in flight collapse to the latest position")
    func collapsesWhileInFlight() {
        var queue = ScrubPreviewRequestQueue()
        _ = queue.request(at: 30)

        // 手指还在动：中间这些落点注定被丢弃，一个请求都不该发出去。
        #expect(queue.request(at: 40) == nil)
        #expect(queue.request(at: 55) == nil)
        #expect(queue.request(at: 61) == nil)
        #expect(queue.inFlight == 30)
        #expect(queue.pending == 61)

        #expect(queue.finish() == 61)
        #expect(queue.inFlight == 61)
    }

    @Test("finishing with nothing queued leaves the queue idle")
    func finishWithoutPending() {
        var queue = ScrubPreviewRequestQueue()
        _ = queue.request(at: 30)

        #expect(queue.finish() == nil)
        #expect(queue.inFlight == nil)
        // 空转之后还能重新接上。
        #expect(queue.request(at: 12) == 12)
    }

    @Test("non-finite and negative positions are refused")
    func rejectsInvalidPositions() {
        var queue = ScrubPreviewRequestQueue()

        #expect(queue.request(at: -1) == nil)
        #expect(queue.request(at: .nan) == nil)
        #expect(queue.request(at: .infinity) == nil)
        #expect(queue.inFlight == nil)
    }

    @Test("reset drops both the in-flight and the queued position")
    func resetClears() {
        var queue = ScrubPreviewRequestQueue()
        _ = queue.request(at: 30)
        _ = queue.request(at: 90)

        queue.reset()

        #expect(queue.inFlight == nil)
        #expect(queue.pending == nil)
        #expect(queue.request(at: 5) == 5)
    }
}
