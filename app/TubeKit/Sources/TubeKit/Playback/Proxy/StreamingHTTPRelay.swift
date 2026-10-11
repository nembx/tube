import Foundation

/// 把 `URLSession` 的 data task 桥接成「先拿响应头、再逐块拿 body」。
///
/// `URLSession.data(for:)` 要等整个响应下载完才返回 —— 用在视频分片上等于把
/// 「边下边播」退化成「下完一片播一片」。`bytes(for:)` 虽是流式但按单字节迭代，
/// 视频吞吐下开销过大，所以这里走 delegate 直接拿原始 `Data` 块。
final class StreamingHTTPRelay: NSObject, URLSessionDataDelegate, @unchecked Sendable {

    /// 一次请求的收敛点：响应头一个 continuation，body 一条 stream。
    private final class Pending: @unchecked Sendable {
        var responseContinuation: CheckedContinuation<HTTPURLResponse, Error>?
        var bodyContinuation: AsyncThrowingStream<Data, Error>.Continuation?
    }

    private let lock = NSLock()
    private var pending: [Int: Pending] = [:]
    private var session: URLSession!

    init(configuration: URLSessionConfiguration) {
        super.init()
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    func invalidate() {
        session.invalidateAndCancel()
    }

    /// 响应头一到就返回；body 通过 stream 边收边给。
    func fetch(
        _ request: URLRequest
    ) async throws -> (HTTPURLResponse, AsyncThrowingStream<Data, Error>) {
        let task = session.dataTask(with: request)
        let slot = Pending()
        let stream = AsyncThrowingStream<Data, Error> { continuation in
            slot.bodyContinuation = continuation
        }
        lock.withLock { pending[task.taskIdentifier] = slot }

        let http = try await withCheckedThrowingContinuation { continuation in
            lock.withLock { slot.responseContinuation = continuation }
            task.resume()
        }
        return (http, stream)
    }

    // MARK: URLSessionDataDelegate

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        let slot = lock.withLock { pending[dataTask.taskIdentifier] }
        let continuation = lock.withLock { () -> CheckedContinuation<HTTPURLResponse, Error>? in
            let held = slot?.responseContinuation
            slot?.responseContinuation = nil
            return held
        }
        guard let http = response as? HTTPURLResponse else {
            continuation?.resume(throwing: URLError(.badServerResponse))
            completionHandler(.cancel)
            return
        }
        continuation?.resume(returning: http)
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let slot = lock.withLock { pending[dataTask.taskIdentifier] }
        slot?.bodyContinuation?.yield(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let slot = lock.withLock { pending.removeValue(forKey: task.taskIdentifier) }
        guard let slot else { return }

        let continuation = lock.withLock { () -> CheckedContinuation<HTTPURLResponse, Error>? in
            let held = slot.responseContinuation
            slot.responseContinuation = nil
            return held
        }
        if let continuation {
            // 响应头都没等到就结束了，只能让 fetch 抛错。
            continuation.resume(throwing: error ?? URLError(.badServerResponse))
            slot.bodyContinuation?.finish()
            return
        }
        slot.bodyContinuation?.finish(throwing: error)
    }
}
