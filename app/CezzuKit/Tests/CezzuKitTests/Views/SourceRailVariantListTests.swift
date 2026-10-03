import Testing

@testable import CezzuKit

@Suite("选源 popover 的条目列表高度")
@MainActor
struct SourceRailVariantListTests {
    @Test("条目多到一定程度就必须能滚")
    func manySourcesExceedAnyPopoverHeight() {
        // 一个站点下几十个资源是常事。列表原来是裸 VStack，撑出屏幕之后
        // 露不出来的条目就再也点不到了。
        let height = SourceRail.estimatedVariantListHeight(sourceCount: 32)
        // 竖屏上限 400、横屏上限 240，32 条两个都放不下 —— 也就是说 ScrollView
        // 不是可选项。这条测试是给「顺手把 ScrollView 拆了」兜底的。
        #expect(height > 400)
    }

    @Test("条目少时高度贴着内容走")
    func fewSourcesStayCompact() {
        let height = SourceRail.estimatedVariantListHeight(sourceCount: 3)
        #expect(height < 240, "三条不该撑到横屏上限，否则短列表会留一大片空白")
        #expect(height > 0)
    }

    @Test("估算高度随条目数单调增长")
    func heightGrowsWithCount() {
        let heights = [1, 2, 8, 32].map {
            SourceRail.estimatedVariantListHeight(sourceCount: $0)
        }
        #expect(heights == heights.sorted())
        #expect(Set(heights).count == heights.count)
    }

    @Test("零条目也给出正数高度")
    func zeroCountStaysPositive() {
        // 分组理论上不会是空的，但高度一旦算成 0，popover 会塌成一条线，
        // 连站点名都看不见。
        #expect(SourceRail.estimatedVariantListHeight(sourceCount: 0) > 0)
        #expect(SourceRail.estimatedVariantListHeight(sourceCount: -1) > 0)
    }
}
