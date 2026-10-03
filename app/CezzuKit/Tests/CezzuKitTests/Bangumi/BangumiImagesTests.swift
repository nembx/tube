import Testing
@testable import CezzuKit

@Suite("BangumiImages")
struct BangumiImagesTests {
    @Test("listBest prefers list-sized covers before original image")
    func listBestPrefersSizedCovers() {
        let images = BangumiImages(
            large: "large",
            common: "common",
            medium: "medium",
            small: "small",
            grid: "grid"
        )

        #expect(images.listBest == "common")
        #expect(images.best == "large")
    }

    @Test("listBest falls back when sized cover URLs are missing")
    func listBestFallsBack() {
        let images = BangumiImages(
            large: "large",
            common: "",
            medium: "",
            small: "small",
            grid: ""
        )

        #expect(images.listBest == "small")
    }

    @Test("legacy large-only images still work in list")
    func listBestFallsBackToLargeForLegacyImageField() {
        let images = BangumiImages(
            large: "large",
            common: "",
            medium: "",
            small: "",
            grid: ""
        )

        #expect(images.listBest == "large")
    }
}
