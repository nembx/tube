import Foundation

/// 规则引擎与规则商店在 v1 抛出的统一错误。
public enum RuleEngineError: Error, Sendable, CustomStringConvertible {
    case invalidURL(String)
    case timeout(rule: String)
    case http(status: Int, rule: String)
    case parse(message: String, rule: String)
    case xpathEvaluation(message: String, rule: String)
    case noResults(rule: String)
    case captchaRequired(rule: String)
    case cancelled

    public var description: String {
        switch self {
        case .invalidURL(let s): return "invalid URL: \(s)"
        case .timeout(let rule): return "timeout while talking to rule '\(rule)'"
        case .http(let status, let rule): return "HTTP \(status) from rule '\(rule)'"
        case .parse(let msg, let rule): return "parse error in rule '\(rule)': \(msg)"
        case .xpathEvaluation(let msg, let rule):
            return "XPath evaluation failed in rule '\(rule)': \(msg)"
        case .noResults(let rule): return "rule '\(rule)' produced no results"
        case .captchaRequired(let rule): return "rule '\(rule)' requires captcha verification"
        case .cancelled: return "operation cancelled"
        }
    }

    /// 面向用户的中文提示。`description` 是给开发者看的，别拿去渲染 UI。
    public var userMessage: String {
        switch self {
        case .invalidURL: return "规则源地址无效"
        case .timeout: return "请求超时，检查网络后重试"
        case .http(let status, _):
            if status == 404 { return "规则源上找不到这条规则（HTTP 404）" }
            return "规则源返回 HTTP \(status)"
        case .parse: return "规则文件无法解析，可能格式不兼容"
        case .xpathEvaluation: return "规则解析失败"
        case .noResults: return "规则源没有返回任何内容"
        case .captchaRequired: return "站点要求验证码"
        case .cancelled: return "已取消"
        }
    }
}
