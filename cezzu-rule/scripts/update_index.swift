#!/usr/bin/env swift
//
// update_index.swift
//
// 扫描 cezzu-rule/rules/*.json，为每条未弃用的规则生成一条 catalog 条目，
// 写入 cezzu-rule/index.json。
//
// 字段：
//   name              ← 规则的 name 字段
//   version           ← 规则的 version 字段
//   useNativePlayer   ← 规则的 useNativePlayer 字段
//   antiCrawlerEnabled ← 规则的 antiCrawlerConfig.enabled，缺省 false
//   author            ← 规则的 author 字段，缺省 ""
//   lastUpdate        ← 优先取 git log -1 --format=%at <file> * 1000，回落到 mtime
//
// 跳过 "deprecated": true 的规则。
//
// 用法：
//   cd cezzu-rule/
//   ./scripts/update_index.swift

import Foundation

// MARK: - paths

let scriptURL = URL(fileURLWithPath: #filePath)
let projectRoot = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let rulesDir = projectRoot.appendingPathComponent("rules")
let indexPath = projectRoot.appendingPathComponent("index.json")

let fileManager = FileManager.default

guard fileManager.fileExists(atPath: rulesDir.path) else {
    fputs("error: \(rulesDir.path) 不存在；请先在 rules/ 下放至少一条 *.json\n", stderr)
    exit(1)
}

// MARK: - helpers

func gitLastUpdateMillis(for file: URL, repoRoot: URL) -> Int? {
    let task = Process()
    task.currentDirectoryURL = repoRoot
    task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    task.arguments = ["git", "log", "-1", "--format=%at", "--", file.path]
    let stdout = Pipe()
    let stderr = Pipe()
    task.standardOutput = stdout
    task.standardError = stderr
    do {
        try task.run()
    } catch {
        return nil
    }
    task.waitUntilExit()
    guard task.terminationStatus == 0 else { return nil }
    let data = stdout.fileHandleForReading.readDataToEndOfFile()
    let raw = String(data: data, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if let secs = Int(raw), secs > 0 {
        return secs * 1000
    }
    return nil
}

func mtimeMillis(for file: URL) -> Int {
    let attrs = (try? fileManager.attributesOfItem(atPath: file.path)) ?? [:]
    if let date = attrs[.modificationDate] as? Date {
        return Int(date.timeIntervalSince1970 * 1000)
    }
    return 0
}

// MARK: - scan

let entries: [URL]
do {
    entries = try fileManager
        .contentsOfDirectory(at: rulesDir, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "json" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
} catch {
    fputs("error: 无法列出 \(rulesDir.path)：\(error)\n", stderr)
    exit(1)
}

var catalog: [[String: Any]] = []
var skippedDeprecated = 0
var skippedInvalid = 0

for file in entries {
    guard let data = try? Data(contentsOf: file) else {
        fputs("warning: 读不了 \(file.lastPathComponent)，跳过\n", stderr)
        skippedInvalid += 1
        continue
    }
    guard
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
        fputs("warning: \(file.lastPathComponent) 不是合法 JSON 对象，跳过\n", stderr)
        skippedInvalid += 1
        continue
    }
    if (object["deprecated"] as? Bool) == true {
        skippedDeprecated += 1
        continue
    }

    let stem = file.deletingPathExtension().lastPathComponent
    let name = (object["name"] as? String) ?? stem
    if name != stem {
        fputs(
            "warning: \(file.lastPathComponent) 文件名 stem 与 name 字段不一致 (\(stem) vs \(name))\n",
            stderr
        )
    }

    let version = (object["version"] as? String) ?? "1.0"
    let useNativePlayer = (object["useNativePlayer"] as? Bool) ?? true
    let antiCrawlerEnabled =
        ((object["antiCrawlerConfig"] as? [String: Any])?["enabled"] as? Bool) ?? false
    let author = (object["author"] as? String) ?? ""
    let lastUpdate = gitLastUpdateMillis(for: file, repoRoot: projectRoot) ?? mtimeMillis(for: file)

    let entry: [String: Any] = [
        "name": name,
        "version": version,
        "useNativePlayer": useNativePlayer,
        "antiCrawlerEnabled": antiCrawlerEnabled,
        "author": author,
        "lastUpdate": lastUpdate,
    ]
    catalog.append(entry)
}

// MARK: - write

do {
    let outData = try JSONSerialization.data(
        withJSONObject: catalog,
        options: [.prettyPrinted, .sortedKeys]
    )
    try outData.write(to: indexPath)
} catch {
    fputs("error: 写 \(indexPath.path) 失败：\(error)\n", stderr)
    exit(1)
}

print("✓ index.json 生成完毕：\(catalog.count) 条 catalog 条目")
if skippedDeprecated > 0 {
    print("  跳过 \(skippedDeprecated) 条 deprecated 规则")
}
if skippedInvalid > 0 {
    print("  跳过 \(skippedInvalid) 条非法文件")
}
print("  路径：\(indexPath.path)")
