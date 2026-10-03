import Foundation

/// 视频嗅探器对外暴露的协议。一次输入：(URL, rule)；一次输出：异步流的候选媒体。
public protocol VideoExtractor: Sendable {
    /// 启动一次嗅探，返回一个 `AsyncStream<ExtractedMedia>`。
    /// 调用方负责 `await stream.first(where: { !$0.isAd })` 获取需要的命中并取消任务。
    func extract(from url: URL, rule: CezzuRule) -> AsyncStream<ExtractedMedia>
}
