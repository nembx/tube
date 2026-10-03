#!/usr/bin/env bash
#
# sync_seed_rules.sh
#
# 把 cezzu-rule/ 里的 rules/*.json 与 index.json 复制进
# CezzuKit/Sources/CezzuKit/Resources/SeedRules/，作为 App 的离线启动种子。
#
# 这个脚本应该在每次 build 前运行 —— Xcode 的 App target 在 Build Phases
# 顶部加一个 "Run Script" pre-build 阶段调用它即可。
#
# 用法：
#   ${SRCROOT}/../scripts/sync_seed_rules.sh
#   （或在 cezzu/ 目录下：./scripts/sync_seed_rules.sh）
#
# 失败语义：找不到 cezzu-rule/ 时打印明确错误并退出非零，build 因此停下。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CEZZU_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$CEZZU_ROOT/.." && pwd)"

CEZZU_RULE_DIR="$REPO_ROOT/cezzu-rule"
SEED_DST="$CEZZU_ROOT/CezzuKit/Sources/CezzuKit/Resources/SeedRules"

if [ ! -d "$CEZZU_RULE_DIR" ]; then
    echo "error: cezzu-rule/ not found at $CEZZU_RULE_DIR" >&2
    echo "       请确认你已经 clone 完整的 monorepo（包含 cezzu-rule/ 子项目）" >&2
    exit 1
fi

if [ ! -d "$CEZZU_RULE_DIR/rules" ]; then
    echo "error: $CEZZU_RULE_DIR/rules 不存在" >&2
    echo "       请确认 cezzu-rule/ 子项目里有 rules/*.json" >&2
    exit 1
fi

if [ ! -f "$CEZZU_RULE_DIR/index.json" ]; then
    echo "error: $CEZZU_RULE_DIR/index.json 不存在" >&2
    echo "       请先在 cezzu-rule/ 下跑 ./scripts/update_index.swift" >&2
    exit 1
fi

mkdir -p "$SEED_DST"

# 清掉旧的 *.json，避免 stale rules（保留目录与 .gitkeep）
find "$SEED_DST" -name '*.json' -type f -delete

cp "$CEZZU_RULE_DIR/index.json" "$SEED_DST/index.json"
cp "$CEZZU_RULE_DIR/rules/"*.json "$SEED_DST/"

count="$(find "$SEED_DST" -name '*.json' -type f | wc -l | tr -d ' ')"
echo "✓ 已同步 $count 个 JSON 文件 (含 index.json) 到 $SEED_DST"
