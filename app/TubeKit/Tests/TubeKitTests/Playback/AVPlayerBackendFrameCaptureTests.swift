import AVFoundation
import Foundation
import Network
import Testing

@testable import TubeKit

/// 连得上、但一个字节都不回的上游。取图管线就是这么卡住的：
/// 源不是不可达（那会当场失败），而是一直吊着。
private final class StallingUpstream: @unchecked Sendable {
    private let lock = NSLock()
    private var listener: NWListener?
    private var connections: [NWConnection] = []

    func start() throws -> UInt16 {
        let listener = try NWListener(using: .tcp, on: .any)
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { state in
            if case .ready = state { ready.signal() }
        }
        listener.newConnectionHandler = { [weak self] connection in
            connection.start(queue: .global())
            self?.lock.withLock { self?.connections.append(connection) }
        }
        listener.start(queue: .global())
        self.listener = listener

        guard ready.wait(timeout: .now() + 5) == .success, let port = listener.port else {
            throw URLError(.cannotConnectToHost)
        }
        return port.rawValue
    }

    func stop() {
        lock.withLock {
            connections.forEach { $0.cancel() }
            connections.removeAll()
        }
        listener?.cancel()
        listener = nil
    }
}

/// 抽帧到底回来了没有。
private actor CaptureWatch {
    private(set) var isFinished = false

    func markFinished() { isFinished = true }
}

@Suite("AVPlayerBackend frame capture")
@MainActor
struct AVPlayerBackendFrameCaptureTests {

    @Test("源吊着不回数据时，抽帧也挡不住拆播放器")
    func stalledSourceDoesNotBlockDispose() async throws {
        let upstream = StallingUpstream()
        let port = try upstream.start()
        defer { upstream.stop() }

        let backend = AVPlayerBackend()
        await backend.load(
            url: URL(string: "http://127.0.0.1:\(port)/stream.m3u8")!,
            headers: [:],
            startAt: 0
        )

        let started = Date()
        let capture = backend.detachedFrameCapture()
        #expect(capture != nil)

        // 关键：抽帧还欠着，拆播放器也必须当场做完。等它的话，关闭播放页时
        // 画面已经没了声音还在响，关闭键也像是没反应。
        backend.dispose()
        #expect(backend.player.currentItem == nil)
        #expect(Date().timeIntervalSince(started) < 1)

        // 确认上面那一步不是因为抽帧提前失败才快的：它这会儿仍然没有结果。
        let watch = CaptureWatch()
        let probe = Task { [capture] in
            _ = await capture?.value
            await watch.markFinished()
        }
        try? await Task.sleep(for: .milliseconds(500))
        #expect(await watch.isFinished == false)

        capture?.cancel()
        probe.cancel()
    }

    @Test("没有装载任何东西时抽不出帧")
    func captureWithoutItemIsNil() {
        let backend = AVPlayerBackend()
        defer { backend.dispose() }

        #expect(backend.detachedFrameCapture() == nil)
    }
}
