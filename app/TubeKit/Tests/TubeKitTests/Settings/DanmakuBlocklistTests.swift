import Testing
@testable import TubeKit

@Suite("弹幕关键词屏蔽")
struct DanmakuBlocklistTests {
    @Test("移除空行并忽略大小写及全半角去重")
    func normalizesKeywords() {
        let blocklist = DanmakuBlocklist(rawValue: " 广告 \r\n\nSpoiler\nＳＰＯＩＬＥＲ\n广告\n")
        #expect(blocklist.keywords == ["广告", "Spoiler"])
        #expect(blocklist.rawValue == "广告\nSpoiler")
    }

    @Test("按子串屏蔽中文、英文及全角内容", arguments: ["这是广告内容", "contains SPOILER here", "contains ｓｐｏｉｌｅｒ here"])
    func matchesSubstrings(text: String) {
        #expect(DanmakuBlocklist(rawValue: "广告\nSpoiler").blocks(text))
    }

    @Test("空列表和未匹配弹幕正常显示")
    func allowsUnmatchedComments() {
        #expect(!DanmakuBlocklist(rawValue: " \n").blocks("正常弹幕"))
        #expect(!DanmakuBlocklist(rawValue: "广告").blocks("正常弹幕"))
        #expect(!DanmakuBlocklist(rawValue: "广告").blocks(""))
    }

    @Test("保存再读取保留相同关键词")
    func roundTrips() {
        let blocklist = DanmakuBlocklist(rawValue: " 广告 \nSpoiler\n广告")
        #expect(DanmakuBlocklist(rawValue: blocklist.rawValue).keywords == blocklist.keywords)
    }
}
