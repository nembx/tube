import Foundation

/// 跨规则并发搜索协调者。每个启用的规则一个子任务，结果通过 `AsyncStream` 流式
/// 推回 caller，让 UI 在第一条结果回来时立刻开始 render。
public protocol SourceSearchCoordinating: Sendable {
    func search(
        keyword: String,
        rules: [CezzuRule]
    ) -> AsyncStream<SearchCoordinator.Update>

    /// 多关键词并发搜索。所有关键词 × 所有规则同时发起。
    func searchAll(
        keywords: [String],
        rules: [CezzuRule]
    ) -> AsyncStream<SearchCoordinator.Update>
}

public actor SearchCoordinator: SourceSearchCoordinating {

    public enum Update: Sendable {
        case ruleStarted(name: String)
        case ruleResults(name: String, results: [SearchResult])
        case ruleFailed(name: String, message: String)
        /// `url` 是命中验证码的真实搜索 URL（规则 searchURL 模板替换 `@keyword` 后的结果），
        /// 让 UI 把 WKWebView 直接 load 到拦截页、而不是无关的 baseURL 首页。
        case ruleCaptchaRequired(name: String, url: URL, userAgent: String)
        case finished
    }

    private let engine: RuleEngine
    private let perRuleTimeoutSeconds: TimeInterval
    private let overallTimeoutSeconds: TimeInterval

    /// - Parameters:
    ///   - perRuleTimeoutSeconds: 单条「关键词 × 规则」请求的上限。计时从任务启动算起，
    ///     而 URLSession 对同一 host 是排队发的（每 host 4~6 条连接），同一站点的多个
    ///     关键词请求会互相排队，所以这个值必须留出排队时间，不能贴着单次 RTT 设。
    ///   - overallTimeoutSeconds: 整轮搜索的兜底上限。结果是流式回吐的，到点前出来的
    ///     都已经渲染了，这个值只负责掐掉长尾。
    public init(
        engine: RuleEngine = LiveRuleEngine(),
        perRuleTimeoutSeconds: TimeInterval = 10,
        overallTimeoutSeconds: TimeInterval = 12
    ) {
        self.engine = engine
        self.perRuleTimeoutSeconds = perRuleTimeoutSeconds
        self.overallTimeoutSeconds = overallTimeoutSeconds
    }

    /// 启动一次搜索，返回一个 `AsyncStream<Update>`。
    public nonisolated func search(
        keyword: String,
        rules: [CezzuRule]
    ) -> AsyncStream<Update> {
        AsyncStream { continuation in
            let task = Task {
                await self.run(
                    keyword: keyword,
                    rules: rules,
                    continuation: continuation
                )
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    /// 多关键词并发搜索。所有 keyword × rule 组合同时发起，超过整轮上限后取消剩余请求。
    public nonisolated func searchAll(
        keywords: [String],
        rules: [CezzuRule]
    ) -> AsyncStream<Update> {
        AsyncStream { continuation in
            let searchTask = Task {
                await self.runAll(
                    keywords: keywords,
                    rules: rules,
                    continuation: continuation
                )
                continuation.finish()
            }
            let deadlineTask = Task {
                let seconds = await self.overallTimeoutSeconds
                try? await Task.sleep(for: .seconds(seconds))
                searchTask.cancel()
                try? await Task.sleep(for: .milliseconds(50))
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in
                searchTask.cancel()
                deadlineTask.cancel()
            }
        }
    }

    private func run(
        keyword: String,
        rules: [CezzuRule],
        continuation: AsyncStream<Update>.Continuation
    ) async {
        let timeout = perRuleTimeoutSeconds
        let engine = self.engine
        await withTaskGroup(of: Void.self) { group in
            for rule in rules {
                group.addTask {
                    continuation.yield(.ruleStarted(name: rule.name))
                    do {
                        let results = try await SearchCoordinator.searchOne(
                            keyword: keyword,
                            rule: rule,
                            engine: engine,
                            timeout: timeout
                        )
                        continuation.yield(.ruleResults(name: rule.name, results: results))
                    } catch let error as RuleEngineError {
                        if case .captchaRequired(let ruleName) = error {
                            let url = rule.resolvedSearchURL(for: keyword)
                                ?? URL(string: rule.baseURL)
                                ?? URL(string: "about:blank")!
                            continuation.yield(
                                .ruleCaptchaRequired(
                                    name: ruleName,
                                    url: url,
                                    userAgent: rule.userAgent
                                )
                            )
                        } else {
                            continuation.yield(.ruleFailed(name: rule.name, message: "\(error)"))
                        }
                    } catch {
                        continuation.yield(.ruleFailed(name: rule.name, message: "\(error)"))
                    }
                }
            }
        }
        continuation.yield(.finished)
    }

    private func runAll(
        keywords: [String],
        rules: [CezzuRule],
        continuation: AsyncStream<Update>.Continuation
    ) async {
        let timeout = perRuleTimeoutSeconds
        let engine = self.engine
        await withTaskGroup(of: Void.self) { group in
            for keyword in keywords {
                for rule in rules {
                    group.addTask {
                        continuation.yield(.ruleStarted(name: rule.name))
                        do {
                            let results = try await SearchCoordinator.searchOne(
                                keyword: keyword,
                                rule: rule,
                                engine: engine,
                                timeout: timeout
                            )
                            continuation.yield(.ruleResults(name: rule.name, results: results))
                        } catch is CancellationError {
                            // 截止时间到达或外部取消，静默忽略
                        } catch let error as RuleEngineError {
                            if case .captchaRequired(let ruleName) = error {
                                let url = rule.resolvedSearchURL(for: keyword)
                                    ?? URL(string: rule.baseURL)
                                    ?? URL(string: "about:blank")!
                                continuation.yield(
                                    .ruleCaptchaRequired(
                                        name: ruleName,
                                        url: url,
                                        userAgent: rule.userAgent
                                    )
                                )
                            } else {
                                continuation.yield(.ruleFailed(name: rule.name, message: "\(error)"))
                            }
                        } catch {
                            continuation.yield(.ruleFailed(name: rule.name, message: "\(error)"))
                        }
                    }
                }
            }
        }
        continuation.yield(.finished)
    }

    private static func searchOne(
        keyword: String,
        rule: CezzuRule,
        engine: RuleEngine,
        timeout: TimeInterval
    ) async throws -> [SearchResult] {
        try await withThrowingTaskGroup(of: [SearchResult].self) { group in
            group.addTask {
                try await engine.search(keyword, with: rule)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw RuleEngineError.timeout(rule: rule.name)
            }
            let result = try await group.next() ?? []
            group.cancelAll()
            return result
        }
    }
}
