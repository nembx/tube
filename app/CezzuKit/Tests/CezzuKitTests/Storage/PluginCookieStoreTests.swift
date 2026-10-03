import Foundation
import Testing
@testable import CezzuKit

@Suite("PluginCookieStore")
struct PluginCookieStoreTests {

    private func makeCookie(
        name: String,
        value: String,
        domain: String = "example.com",
        path: String = "/",
        secure: Bool = false
    ) -> HTTPCookie {
        HTTPCookie(properties: [
            .name: name,
            .value: value,
            .domain: domain,
            .path: path,
            .secure: secure ? "TRUE" : "FALSE",
        ])!
    }

    @Test("set stores cookies scoped by rule name")
    func setAndFetch() async {
        let store = PluginCookieStore()
        await store.set([makeCookie(name: "a", value: "1")], for: "ruleA")
        await store.set([makeCookie(name: "b", value: "2")], for: "ruleB")
        let a = await store.cookies(for: "ruleA")
        let b = await store.cookies(for: "ruleB")
        #expect(a.count == 1)
        #expect(a.first?.name == "a")
        #expect(b.first?.name == "b")
    }

    @Test("merge overwrites same-name cookie, keeps others")
    func mergeOverwrites() async {
        let store = PluginCookieStore()
        await store.set([makeCookie(name: "a", value: "1"), makeCookie(name: "b", value: "2")], for: "r")
        await store.merge([makeCookie(name: "a", value: "UPDATED"), makeCookie(name: "c", value: "3")], for: "r")
        let cookies = await store.cookies(for: "r")
        let dict = Dictionary(uniqueKeysWithValues: cookies.map { ($0.name, $0.value) })
        #expect(dict["a"] == "UPDATED")
        #expect(dict["b"] == "2")
        #expect(dict["c"] == "3")
    }

    @Test("matching URL filters by domain and path")
    func matchingURL() async {
        let store = PluginCookieStore()
        let cookies = [
            makeCookie(name: "root", value: "1", domain: "example.com", path: "/"),
            makeCookie(name: "scoped", value: "2", domain: "example.com", path: "/api"),
            makeCookie(name: "sub", value: "3", domain: ".example.com", path: "/"),
            makeCookie(name: "other", value: "4", domain: "other.com", path: "/"),
        ]
        await store.set(cookies, for: "r")

        let matched = await store.cookies(for: "r", matching: URL(string: "https://api.example.com/api/list")!)
        let names = Set(matched.map(\.name))
        #expect(names.contains("sub"))
        #expect(!names.contains("other"))
        #expect(!names.contains("root"))
        #expect(!names.contains("scoped"))
    }

    @Test("secure cookie excluded from http URLs")
    func secureCookieHTTP() async {
        let store = PluginCookieStore()
        await store.set([makeCookie(name: "s", value: "1", secure: true)], for: "r")
        let matched = await store.cookies(for: "r", matching: URL(string: "http://example.com/")!)
        #expect(matched.isEmpty)
    }

    @Test("clear removes cookies for one rule only")
    func clearIsolates() async {
        let store = PluginCookieStore()
        await store.set([makeCookie(name: "a", value: "1")], for: "r1")
        await store.set([makeCookie(name: "b", value: "2")], for: "r2")
        await store.clear("r1")
        let r1 = await store.cookies(for: "r1")
        let r2 = await store.cookies(for: "r2")
        #expect(r1.isEmpty)
        #expect(r2.count == 1)
    }
}
