import Foundation
import Testing
@testable import TubeKit

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// 旧接口 `/search/subject/{keywords}` 的真实响应形态，多个 suite 共用。
///
/// `rank` 在顶层（v0 在 `rating.rank` 里），图片是 `http://`（ATS 会拦），
/// `collection` 的键与 v0 一致。
enum BangumiLegacyFixtures {
    static let restrictedSubject = """
        {
            "results": 1,
            "list": [
                {
                    "id": 36954,
                    "url": "http://bgm.tv/subject/36954",
                    "type": 2,
                    "name": "Restricted Subject",
                    "name_cn": "受限条目",
                    "summary": "只有老接口能召回的条目。",
                    "eps": 1,
                    "eps_count": 1,
                    "air_date": "2007-02-23",
                    "air_weekday": 5,
                    "rating": {"total": 241, "score": 6.4},
                    "rank": 5532,
                    "images": {
                        "large": "http://lain.bgm.tv/pic/cover/l/92/cf/36954_DR777.jpg",
                        "common": "http://lain.bgm.tv/pic/cover/c/92/cf/36954_DR777.jpg",
                        "medium": "http://lain.bgm.tv/pic/cover/m/92/cf/36954_DR777.jpg",
                        "small": "http://lain.bgm.tv/pic/cover/s/92/cf/36954_DR777.jpg",
                        "grid": "http://lain.bgm.tv/pic/cover/g/92/cf/36954_DR777.jpg"
                    },
                    "collection": {"wish": 163, "collect": 430, "doing": 13, "on_hold": 36, "dropped": 38}
                }
            ]
        }
        """
}

/// 给 stub handler 用的最小可变盒子 —— handler 是 `@Sendable` 闭包，不能直接捕获 `var`。
final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value

    init(_ value: Value) {
        self.storage = value
    }

    var value: Value {
        get { lock.withLock { storage } }
        set { lock.withLock { storage = newValue } }
    }
}

/// 老接口响应形态的解码 —— 三个 error case 都是实测过的真实返回。
@Suite("BangumiLegacySearch decoding")
struct BangumiLegacyDecodingTests {

    @Test("maps top-level rank, eps_count fallback and collection")
    func decodesSubject() throws {
        let response = try JSONDecoder().decode(
            BangumiLegacySearchResponse.self,
            from: Data(BangumiLegacyFixtures.restrictedSubject.utf8)
        )
        #expect(response.results == 1)
        let item = try #require(response.list.first).toBangumiItem()
        #expect(item.id == 36954)
        #expect(item.nameCn == "受限条目")
        #expect(item.rank == 5532)
        #expect(item.ratingScore == 6.4)
        #expect(item.ratingTotal == 241)
        #expect(item.episodeCount == 1)
        #expect(item.collection?.onHold == 36)
        // 老接口没有这些字段，必须留空而不是崩。
        #expect(item.tags.isEmpty)
        #expect(item.infobox.isEmpty)
    }

    /// ATS 会拦 http 图片，映射时必须提升到 https。
    @Test("upgrades http cover URLs to https")
    func upgradesImageScheme() throws {
        let response = try JSONDecoder().decode(
            BangumiLegacySearchResponse.self,
            from: Data(BangumiLegacyFixtures.restrictedSubject.utf8)
        )
        let images = try #require(response.list.first).images
        #expect(images.large.hasPrefix("https://"))
        #expect(images.grid.hasPrefix("https://"))
        #expect(!images.best.hasPrefix("http://"))
    }

    /// `results` 非 0 但 `list` 为 null 是老接口的已知行为，不能抛。
    @Test("tolerates null list alongside a non-zero results count")
    func decodesNullList() throws {
        let json = #"{"results": 1000, "list": null}"#
        let response = try JSONDecoder().decode(
            BangumiLegacySearchResponse.self, from: Data(json.utf8)
        )
        #expect(response.results == 1000)
        #expect(response.list.isEmpty)
    }

    /// 出错时 HTTP 是 200，body 变成错误对象 —— 必须能识别出来。
    @Test("recognizes the 200-with-error-body envelope")
    func decodesErrorEnvelope() throws {
        let json = #"{"request":"/search/subject/Fate%2FZero","code":404,"error":"Not Found"}"#
        let envelope = try JSONDecoder().decode(
            BangumiLegacyErrorEnvelope.self, from: Data(json.utf8)
        )
        #expect(envelope.code == 404)
    }

    /// path 里的非法字符会让服务端直接 404，必须先换成空格。
    @Test("sanitizes keywords that break the path-based endpoint")
    func sanitizesKeyword() {
        #expect(BangumiLegacySearch.sanitizeKeyword("Fate/Zero") == "Fate Zero")
        #expect(BangumiLegacySearch.sanitizeKeyword("K-ON!") == "K-ON")
        #expect(BangumiLegacySearch.sanitizeKeyword("100%") == "100")
        #expect(BangumiLegacySearch.sanitizeKeyword("  多余   空格  ") == "多余 空格")
        // 全角星号之类的合法字符不该被吃掉。
        #expect(BangumiLegacySearch.sanitizeKeyword("少女☆歌劇") == "少女☆歌劇")
    }
}

/// 合流规则本身 —— 不打网络，纯函数。
@Suite("BangumiSearchPage merge")
struct BangumiSearchPageMergeTests {

    private func item(_ id: Int, _ name: String, _ nameCn: String = "") -> BangumiItem {
        BangumiItem(
            id: id, name: name, nameCn: nameCn.isEmpty ? name : nameCn,
            summary: "", airDate: "", rank: 0, ratingScore: 0,
            images: .empty, tags: []
        )
    }

    /// v0 完全召回不到的条目排在第 20 位等于没找到，必须置顶。
    @Test("promotes legacy-only title matches to the front")
    func promotesLegacyOnlyMatches() {
        let merged = BangumiSearchPage.merge(
            v0Items: [item(1, "别的东西"), item(2, "另一个")],
            legacyItems: [item(99, "Restricted Subject", "受限条目")],
            keyword: "受限条目"
        )
        #expect(merged.map(\.id) == [99, 1, 2])
    }

    /// v0 已经给过的条目不能重复出现 —— v0 那份有 tags，是权威来源。
    @Test("drops legacy duplicates already returned by v0")
    func dropsDuplicates() {
        let merged = BangumiSearchPage.merge(
            v0Items: [item(99, "受限条目")],
            legacyItems: [item(99, "受限条目")],
            keyword: "受限条目"
        )
        #expect(merged.map(\.id) == [99])
    }

    /// 旧接口靠 summary 命中的条目既没有元数据又会搅乱排序，丢掉。
    @Test("discards legacy hits whose title does not contain the keyword")
    func discardsNonTitleMatches() {
        let merged = BangumiSearchPage.merge(
            v0Items: [item(1, "甲")],
            legacyItems: [item(50, "摘要里才提到关键词的片子")],
            keyword: "受限条目"
        )
        #expect(merged.map(\.id) == [1])
    }

    /// 标题匹配忽略大小写与空白。
    @Test("matches titles ignoring case and whitespace")
    func matchesIgnoringCaseAndWhitespace() {
        let merged = BangumiSearchPage.merge(
            v0Items: [],
            legacyItems: [item(7, "Fate Zero")],
            keyword: "fatezero"
        )
        #expect(merged.map(\.id) == [7])
    }

    /// 纯 tag 搜索没有关键词可比，旧通道的东西一律不并进来。
    @Test("keeps v0 results untouched when there is no keyword")
    func emptyKeywordKeepsV0Only() {
        let merged = BangumiSearchPage.merge(
            v0Items: [item(1, "甲")],
            legacyItems: [item(2, "乙")],
            keyword: "   "
        )
        #expect(merged.map(\.id) == [1])
    }
}
