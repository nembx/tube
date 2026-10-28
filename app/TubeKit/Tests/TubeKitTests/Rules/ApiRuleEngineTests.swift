import Foundation
import Testing
@testable import TubeKit

@Suite("RestrictedJSONPath")
struct RestrictedJSONPathTests {
    @Test("allows fields, quoted fields, indexes and wildcards")
    func allowsSupported() throws {
        for path in [
            "$",
            "$.data.videos[*]",
            "$['data']['play-sources'][0]",
        ] {
            try RestrictedJSONPath.validate(path)
        }
    }

    @Test("rejects filters, recursive descent and expressions")
    func rejectsUnsupported() {
        for path in [
            "$..videos",
            "$.videos[?(@.enabled)]",
            "$.videos[0:2]",
            "$.videos.length()",
        ] {
            #expect(throws: RestrictedJSONPath.FormatError.self) {
                try RestrictedJSONPath.validate(path)
            }
        }
    }

    @Test("reads nested wildcard lists")
    func readWildcard() throws {
        let doc: [String: Any] = [
            "data": [
                "videos": [
                    ["name": "A", "id": "1"],
                    ["name": "B", "id": "2"],
                ]
            ]
        ]
        let nodes = try RestrictedJSONPath.read(doc, expression: "$.data.videos[*]")
        #expect(nodes.count == 2)
        let name = try RestrictedJSONPath.readFirst(nodes[0], expression: "$.name")
        #expect(ApiRuleEngineTestsHelpers.string(name) == "A")
    }
}

@Suite("ApiRuleEngine")
struct ApiRuleEngineTests {
    @Test("prepares typed request placeholders")
    func prepareRequest() throws {
        let request = try ApiRuleEngine.prepareRequest(
            ApiRequestConfig(
                method: "post",
                url: "https://example.com/videos/@source",
                headers: ["X-Keyword": "@keyword"],
                query: ["q": "@keyword", "page": "1"],
                bodyType: .json,
                bodyJSON: #"{"source":"@source","label":"video-@source"}"#
            ),
            variables: ["source": "a/b", "keyword": "测试"]
        )
        #expect(request.method == "POST")
        #expect(request.url.absoluteString.hasPrefix("https://example.com/videos/a%2Fb"))
        #expect(request.headers["X-Keyword"] == "测试")
        #expect(request.url.query?.contains("q=") == true)
        #expect(request.body != nil)
    }

    @Test("ignores inactive request bodies for GET requests")
    func ignoreBodyOnGET() throws {
        let request = try ApiRuleEngine.prepareRequest(
            ApiRequestConfig(
                method: "GET",
                url: "https://example.com/search",
                bodyType: .json,
                bodyJSON: #"{"unused":"@missing"}"#
            ),
            variables: [:]
        )
        #expect(request.body == nil)
    }

    @Test("parses Liangzi-style search and delimited chapters")
    func parseDelimited() throws {
        let searchRaw = Data(
            #"""
            {
              "code": 1,
              "list": [
                {"vod_id": 22639, "vod_name": "吞噬星空"}
              ]
            }
            """#.utf8
        )
        let search = try ApiRuleEngine.parseSearch(
            data: searchRaw,
            config: ApiSearchConfig(
                listPath: "$.list[*]",
                namePath: "$.vod_name",
                sourcePath: "$.vod_id"
            ),
            ruleName: "liangzi"
        )
        #expect(search.count == 1)
        #expect(search[0].title == "吞噬星空")
        #expect(ApiRuleEngine.source(from: search[0].detailURL) == "22639")

        let chapterRaw = Data(
            #"""
            {
              "list": [{
                "vod_play_from": "线路A$$$线路B",
                "vod_play_url": "第01集$https://cdn-a.test/1.m3u8#第02集$https://cdn-a.test/2.m3u8$$$正片$https://cdn-b.test/main.m3u8"
              }]
            }
            """#.utf8
        )
        let roads = try ApiRuleEngine.parseChapters(
            data: chapterRaw,
            config: ApiChapterConfig(
                format: .delimited,
                episodeUrlPath: "",
                roadNamesPath: "$.list[0].vod_play_from",
                roadEpisodesPath: "$.list[0].vod_play_url"
            ),
            source: "22639",
            baseURL: "https://lzizy.net/"
        )
        #expect(roads.count == 2)
        #expect(roads[0].label == "线路A")
        #expect(roads[0].episodes.map(\.title) == ["第01集", "第02集"] as [String])
        #expect(roads[0].episodes[0].url.absoluteString == "https://cdn-a.test/1.m3u8")
        #expect(roads[1].label == "线路B")
        #expect(roads[1].episodes[0].url.absoluteString == "https://cdn-b.test/main.m3u8")
    }

    @Test("parses TvTFun chapters and constructs playback page URLs")
    func parseTvTFunChapters() throws {
        let payload: [String: Any] = [
            "data": [
                "slug": "28431",
                "playSources": [
                    [
                        "name": "线路C",
                        "episodes": [
                            ["name": "第01集", "url": "protected"],
                            ["name": "第02集", "url": "protected"],
                        ],
                    ],
                    [
                        "name": "线路D",
                        "episodes": [
                            ["name": "第01集", "url": "protected"],
                        ],
                    ],
                ],
            ]
        ]
        let raw = try JSONSerialization.data(withJSONObject: payload)
        let roads = try ApiRuleEngine.parseChapters(
            data: raw,
            config: ApiChapterConfig(
                roadsPath: "$.data.playSources[*]",
                roadNamePath: "$.name",
                episodesPath: "$.episodes[*]",
                episodeNamePath: "$.name",
                episodeUrlPath: "",
                variables: ["slug": "$.data.slug"],
                episodePage: ApiEpisodePageConfig(
                    url: "https://www.tvtfun.net/video/@slug/play",
                    query: [
                        "source": "@roadIndex",
                        "episode": "@episodeIndex",
                    ]
                )
            ),
            source: "cmp2x3ot91k1qi9m8zglverqd",
            baseURL: "https://www.tvtfun.net/"
        )
        #expect(roads.count == 2)
        #expect(
            roads[0].episodes[1].url.absoluteString
                == "https://www.tvtfun.net/video/28431/play?episode=1&source=0"
        )
        #expect(
            roads[1].episodes[0].url.absoluteString
                == "https://www.tvtfun.net/video/28431/play?episode=0&source=1"
        )
    }

    @Test("renders every documented episode page template variable")
    func allEpisodePageVariables() throws {
        let payload: [String: Any] = [
            "data": [
                "slug": "abc",
                "roads": [
                    [
                        "name": "线路",
                        "episodes": [
                            ["name": "第01集", "url": "ep-token"]
                        ],
                    ]
                ],
            ]
        ]
        let raw = try JSONSerialization.data(withJSONObject: payload)
        let roads = try ApiRuleEngine.parseChapters(
            data: raw,
            config: ApiChapterConfig(
                episodeUrlPath: "$.url",
                variables: ["slug": "$.data.slug"],
                episodePage: ApiEpisodePageConfig(
                    url: "https://example.com/@slug/@episodeUrl",
                    query: [
                        "ri": "@roadIndex",
                        "rn": "@roadNumber",
                        "ei": "@episodeIndex",
                        "en": "@episodeNumber",
                        "src": "@source",
                    ]
                )
            ),
            source: "vid-1",
            baseURL: "https://example.com/"
        )
        #expect(
            roads[0].episodes[0].url.absoluteString
                == "https://example.com/abc/ep-token?ei=0&en=1&ri=0&rn=1&src=vid-1"
        )
    }

    @Test("keeps default nested road names gapless without changing source index")
    func gaplessRoadNames() throws {
        let payload: [String: Any] = [
            "data": [
                "roads": [
                    ["episodes": [] as [Any]],
                    [
                        "episodes": [
                            ["name": "第01集"]
                        ]
                    ],
                ]
            ]
        ]
        let raw = try JSONSerialization.data(withJSONObject: payload)
        let roads = try ApiRuleEngine.parseChapters(
            data: raw,
            config: ApiChapterConfig(
                roadNamePath: "",
                episodeUrlPath: "",
                episodePage: ApiEpisodePageConfig(
                    url: "/play",
                    query: ["source": "@roadIndex"]
                )
            ),
            source: "id",
            baseURL: "https://example.com/"
        )
        #expect(roads.count == 1)
        #expect(roads[0].label == "播放线路1")
        #expect(roads[0].episodes[0].url.absoluteString == "https://example.com/play?source=1")
        #expect(roads[0].index == 1)
    }

    @Test("TvTFun rule JSON decodes with API search and XPath chapters")
    func decodeTvTFunRule() throws {
        let url = Bundle.tubeKit.url(
            forResource: "SeedRules/TvTFun",
            withExtension: "json"
        )
        #expect(url != nil)
        let data = try Data(contentsOf: url!)
        // strip deprecated if present for decoding path via object check
        let rule = try JSONDecoder().decode(TubeRule.self, from: data)
        #expect(rule.name == "TvTFun")
        #expect(rule.searchMode == .api)
        #expect(rule.chapterMode == .xpath)
        #expect(rule.searchApiConfig?.listPath == "$.data.items[*]")
        #expect(rule.searchApiConfig?.sourceTemplate == "https://www.tvtfun.net/watch/@source/1")
    }

    @Test("source templates encode ids and accept placeholders after letters")
    func sourceTemplate() throws {
        let results = try ApiRuleEngine.parseSearch(
            data: Data(#"{"data":[{"name":"Demo","url":"a/b?c&d"}]}"#.utf8),
            config: ApiSearchConfig(sourceTemplate: "https://example.com/GV@source"),
            ruleName: "demo", chapterMode: .xpath, baseURL: "https://example.com/"
        )
        #expect(results.first?.detailURL.absoluteString == "https://example.com/GVa%2Fb%3Fc%26d")
        #expect(throws: RestrictedJSONPath.FormatError.self) {
            try ApiRuleEngine.validateSearchConfig(
                ApiSearchConfig(sourceTemplate: "https://example.com/static")
            )
        }
    }

    @Test("JSON request bodies preserve types and safely substitute quoted keywords")
    func typedBody() throws {
        let raw = Data(#"""
        {"method":"POST","url":"https://example.com/search","bodyType":"json",
         "body":{"q":"@keyword","page":1,"enabled":true,"ratio":1.5,
                 "nested":{"values":[false,null,"@keyword"]}}}
        """#.utf8)
        let decoded = try JSONDecoder().decode(ApiRequestConfig.self, from: raw)
        let restored = try JSONDecoder().decode(
            ApiRequestConfig.self, from: JSONEncoder().encode(decoded)
        )
        let keyword = "a\"b\\c\n&d"
        let request = try ApiRuleEngine.prepareRequest(restored, variables: ["keyword": keyword])
        let body = try #require(request.body)
        let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(object["q"] as? String == keyword)
        #expect(object["page"] as? Int == 1)
        #expect(object["page"] as? String == nil)
        #expect(object["enabled"] as? Bool == true)
        #expect(object["ratio"] as? Double == 1.5)
        let nested = try #require(object["nested"] as? [String: Any])
        let values = try #require(nested["values"] as? [Any])
        #expect(values[0] as? Bool == false)
        #expect(values[1] is NSNull)
        #expect(values[2] as? String == keyword)
    }
}

enum ApiRuleEngineTestsHelpers {
    static func string(_ value: Any?) -> String {
        guard let value else { return "" }
        if let s = value as? String { return s }
        return String(describing: value)
    }
}
