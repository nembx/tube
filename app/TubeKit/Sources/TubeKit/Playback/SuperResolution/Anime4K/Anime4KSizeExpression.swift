import Foundation

/// 一张纹理的像素尺寸。渲染图里到处传，所以做成最小的值类型。
public struct Anime4KTextureSize: Equatable, Hashable, Sendable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    public static let zero = Anime4KTextureSize(width: 0, height: 0)

    public var isEmpty: Bool { width <= 0 || height <= 0 }
}

/// mpv user-shader 的逆波兰表达式求值器。
///
/// `//!WIDTH` / `//!HEIGHT` / `//!WHEN` 三个指令的值都是这个格式，例如：
///
/// - `MAIN.w` → MAIN 纹理的宽
/// - `conv2d_last_tf.w 2 *` → 那张纹理的宽乘 2
/// - `OUTPUT.w MAIN.w / 1.200 >` → 放大倍率是否超过 1.2
/// - `OUTPUT.w NATIVE.w / 2.0 < OUTPUT.h NATIVE.h / 2.0 < *` → 两个条件同时成立
///
/// 布尔量用 0 / 1 表示，所以 `*` 兼任逻辑与、`+` 兼任逻辑或 —— 这是 mpv 的约定，
/// 不是我们的发明。
public enum Anime4KSizeExpression {
    public enum EvaluationError: Error, Equatable, Sendable {
        /// 表达式是空的。调用方应该在解析阶段就用默认值兜住，走到求值说明 manifest 有问题。
        case emptyExpression
        /// 引用了一张当前不存在的纹理（拼错，或者 pass 顺序错了）。
        case unknownIdentifier(String)
        /// 运算符要两个操作数但栈里不够。
        case stackUnderflow(op: String)
        /// 算完之后栈里剩下的不是恰好一个值。
        case unbalancedStack(remaining: Int)
        case divisionByZero
        case unknownToken(String)
    }

    /// 求值。`symbols` 是当前所有已知纹理的尺寸表（键是 `MAIN` / `OUTPUT` / `conv2d_tf` 这类名字）。
    public static func evaluate(
        _ tokens: [String],
        symbols: [String: Anime4KTextureSize]
    ) throws -> Double {
        guard !tokens.isEmpty else { throw EvaluationError.emptyExpression }

        var stack: [Double] = []
        stack.reserveCapacity(tokens.count)

        for token in tokens {
            if let value = Double(token) {
                stack.append(value)
                continue
            }

            if let value = try lookup(token, in: symbols) {
                stack.append(value)
                continue
            }

            guard isOperator(token) else {
                throw EvaluationError.unknownToken(token)
            }

            if token == "!" {
                guard let a = stack.popLast() else {
                    throw EvaluationError.stackUnderflow(op: token)
                }
                stack.append(a == 0 ? 1 : 0)
                continue
            }

            guard stack.count >= 2 else {
                throw EvaluationError.stackUnderflow(op: token)
            }
            let b = stack.removeLast()
            let a = stack.removeLast()
            stack.append(try apply(token, a, b))
        }

        guard stack.count == 1 else {
            throw EvaluationError.unbalancedStack(remaining: stack.count)
        }
        return stack[0]
    }

    /// `//!WHEN` 专用：空表达式视为「恒执行」，非零视为真。
    public static func evaluateCondition(
        _ tokens: [String],
        symbols: [String: Anime4KTextureSize]
    ) throws -> Bool {
        if tokens.isEmpty { return true }
        return try evaluate(tokens, symbols: symbols) != 0
    }

    /// `//!WIDTH` / `//!HEIGHT` 专用：结果向下取整并至少为 1。
    ///
    /// 取整方向跟着 mpv 走（它也是截断），否则 `AutoDownscalePre` 之类
    /// 刚好卡在整数边界的 pass 会和上游差一个像素。
    public static func evaluateDimension(
        _ tokens: [String],
        symbols: [String: Anime4KTextureSize]
    ) throws -> Int {
        let value = try evaluate(tokens, symbols: symbols)
        guard value.isFinite else { throw EvaluationError.divisionByZero }
        return max(1, Int(value))
    }

    // MARK: - private

    private static func lookup(
        _ token: String,
        in symbols: [String: Anime4KTextureSize]
    ) throws -> Double? {
        guard let dotIndex = token.lastIndex(of: ".") else { return nil }
        let name = String(token[token.startIndex..<dotIndex])
        let field = String(token[token.index(after: dotIndex)...])
        guard field == "w" || field == "h" else { return nil }

        guard let size = symbols[name] else {
            throw EvaluationError.unknownIdentifier(name)
        }
        return field == "w" ? Double(size.width) : Double(size.height)
    }

    private static func isOperator(_ token: String) -> Bool {
        switch token {
        case "+", "-", "*", "/", ">", "<", ">=", "<=", "=", "!=", "!":
            return true
        default:
            return false
        }
    }

    private static func apply(_ op: String, _ a: Double, _ b: Double) throws -> Double {
        switch op {
        case "+": return a + b
        case "-": return a - b
        case "*": return a * b
        case "/":
            guard b != 0 else { throw EvaluationError.divisionByZero }
            return a / b
        case ">": return a > b ? 1 : 0
        case "<": return a < b ? 1 : 0
        case ">=": return a >= b ? 1 : 0
        case "<=": return a <= b ? 1 : 0
        case "=": return a == b ? 1 : 0
        case "!=": return a != b ? 1 : 0
        default: throw EvaluationError.unknownToken(op)
        }
    }
}
