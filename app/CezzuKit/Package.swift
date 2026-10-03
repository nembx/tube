// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CezzuKit",
    defaultLocalization: "zh-Hans",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "CezzuKit",
            targets: ["CezzuKit"]
        ),
        // 一个 SwiftPM executable，让你不用建 Xcode workspace 就能直接
        // `swift run CezzuMac` 把整个 App 跑起来。
        // 不带 .app bundle / 不入沙盒；正式上架前再用 README 里的 Xcode 流程。
        .executable(name: "CezzuMac", targets: ["CezzuMac"]),
    ],
    dependencies: [
        .package(url: "https://github.com/tid-kijyun/Kanna.git", from: "5.3.0")
    ],
    targets: [
        .target(
            name: "CezzuKit",
            dependencies: [
                .product(name: "Kanna", package: "Kanna")
            ],
            resources: [
                .copy("Resources/ThirdPartyNotices.txt"),
                .copy("Resources/SeedRules"),
                .copy("Resources/inject_start.js"),
                .copy("Resources/inject_end.js"),
                // Anime4K 的 .metal 是当资源拷进去的，不参与编译期构建 ——
                // 编译期编 Metal 要求构建机装了 Metal 离线工具链（几 GB），
                // 不该成为 `swift build` / CI 的硬依赖。运行时编译的取舍见
                // Playback/SuperResolution/Anime4K/Anime4KLibraryLoader.swift。
                .copy("Resources/Anime4K"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableExperimentalFeature("StrictConcurrency"),
            ]
            // MetalFX：模拟器 SDK 通常没有该模块。源码用 `#if canImport(MetalFX)` 兜底；
            // 真机编译时由 `import MetalFX` 自动链接，不要在此强制 link（会搞挂 simulator）。
        ),
        .executableTarget(
            name: "CezzuMac",
            dependencies: ["CezzuKit"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "CezzuKitTests",
            dependencies: ["CezzuKit"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
    ]
)
