import Testing

@testable import TubeKit

@Suite("Anime4KSizeExpression")
struct Anime4KSizeExpressionTests {
    private let symbols: [String: Anime4KTextureSize] = [
        "MAIN": Anime4KTextureSize(width: 1920, height: 1080),
        "NATIVE": Anime4KTextureSize(width: 1920, height: 1080),
        "OUTPUT": Anime4KTextureSize(width: 3840, height: 2160),
        "conv2d_last_tf": Anime4KTextureSize(width: 960, height: 540),
    ]

    @Test("读纹理的宽高")
    func readsTextureDimensions() throws {
        #expect(try Anime4KSizeExpression.evaluate(["MAIN.w"], symbols: symbols) == 1920)
        #expect(try Anime4KSizeExpression.evaluate(["MAIN.h"], symbols: symbols) == 1080)
    }

    @Test("逆波兰算术：conv2d_last_tf.w 2 *")
    func evaluatesArithmetic() throws {
        let value = try Anime4KSizeExpression.evaluate(
            ["conv2d_last_tf.w", "2", "*"],
            symbols: symbols
        )
        #expect(value == 1920)
    }

    @Test("比较运算产出 0 / 1")
    func comparisonYieldsBoolean() throws {
        // 上游 Upscale 链的门槛：放大倍率要超过 1.2 才值得跑。
        let tokens = ["OUTPUT.w", "MAIN.w", "/", "1.200", ">"]
        #expect(try Anime4KSizeExpression.evaluate(tokens, symbols: symbols) == 1)
    }

    @Test("乘法兼任逻辑与")
    func multiplicationActsAsLogicalAnd() throws {
        // AutoDownscalePre_x2 的 //!WHEN 就是这个形状。
        let tokens = [
            "OUTPUT.w", "NATIVE.w", "/", "2.0", "<",
            "OUTPUT.h", "NATIVE.h", "/", "2.0", "<", "*",
        ]
        // 倍率正好是 2.0，不满足「小于 2」，两边都是 0。
        #expect(try Anime4KSizeExpression.evaluate(tokens, symbols: symbols) == 0)
    }

    @Test("取非")
    func negation() throws {
        #expect(try Anime4KSizeExpression.evaluate(["0", "!"], symbols: symbols) == 1)
        #expect(try Anime4KSizeExpression.evaluate(["3", "!"], symbols: symbols) == 0)
    }

    @Test("空的 WHEN 视为恒执行")
    func emptyConditionRunsAlways() throws {
        #expect(try Anime4KSizeExpression.evaluateCondition([], symbols: symbols))
    }

    @Test("非零 WHEN 为真")
    func nonZeroConditionIsTrue() throws {
        #expect(try Anime4KSizeExpression.evaluateCondition(["1"], symbols: symbols))
        #expect(try Anime4KSizeExpression.evaluateCondition(["0"], symbols: symbols) == false)
    }

    @Test("尺寸求值截断取整且至少为 1")
    func dimensionTruncatesAndClamps() throws {
        let symbols = ["A": Anime4KTextureSize(width: 5, height: 5)]
        // 5 / 2 = 2.5 -> 2（跟着 mpv 的截断走，不是四舍五入）
        #expect(try Anime4KSizeExpression.evaluateDimension(["A.w", "2", "/"], symbols: symbols) == 2)
        // 5 / 100 = 0.05 -> 至少 1，不能出现 0 宽纹理
        #expect(try Anime4KSizeExpression.evaluateDimension(["A.w", "100", "/"], symbols: symbols) == 1)
    }

    // MARK: - 错误分支

    @Test("空表达式报错")
    func emptyExpressionThrows() {
        #expect(throws: Anime4KSizeExpression.EvaluationError.emptyExpression) {
            try Anime4KSizeExpression.evaluate([], symbols: symbols)
        }
    }

    @Test("引用不存在的纹理报错")
    func unknownIdentifierThrows() {
        #expect(throws: Anime4KSizeExpression.EvaluationError.unknownIdentifier("NOPE")) {
            try Anime4KSizeExpression.evaluate(["NOPE.w"], symbols: symbols)
        }
    }

    @Test("操作数不够报错")
    func stackUnderflowThrows() {
        #expect(throws: Anime4KSizeExpression.EvaluationError.stackUnderflow(op: "*")) {
            try Anime4KSizeExpression.evaluate(["2", "*"], symbols: symbols)
        }
        #expect(throws: Anime4KSizeExpression.EvaluationError.stackUnderflow(op: "!")) {
            try Anime4KSizeExpression.evaluate(["!"], symbols: symbols)
        }
    }

    @Test("算完栈里剩多个值报错")
    func unbalancedStackThrows() {
        #expect(throws: Anime4KSizeExpression.EvaluationError.unbalancedStack(remaining: 2)) {
            try Anime4KSizeExpression.evaluate(["1", "2"], symbols: symbols)
        }
    }

    @Test("除零报错")
    func divisionByZeroThrows() {
        #expect(throws: Anime4KSizeExpression.EvaluationError.divisionByZero) {
            try Anime4KSizeExpression.evaluate(["1", "0", "/"], symbols: symbols)
        }
    }

    @Test("不认识的 token 报错")
    func unknownTokenThrows() {
        #expect(throws: Anime4KSizeExpression.EvaluationError.unknownToken("%")) {
            try Anime4KSizeExpression.evaluate(["1", "2", "%"], symbols: symbols)
        }
        // 有点但字段不是 w / h —— 当作未知 token，不要静默当成 0。
        #expect(throws: Anime4KSizeExpression.EvaluationError.unknownToken("MAIN.z")) {
            try Anime4KSizeExpression.evaluate(["MAIN.z"], symbols: symbols)
        }
    }
}
