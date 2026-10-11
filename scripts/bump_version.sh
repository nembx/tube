#!/bin/bash
# bump_version.sh — 改 version.json 里的版本号并重新生成 xcconfig
# 用法：./scripts/bump_version.sh 0.2.0
#   iOS 与 macOS 同步改成同一个版本；build 号保持不变（CI 会用 run number 覆盖）。
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-}"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "用法: $0 <major.minor.patch>，例如 $0 0.2.0" >&2
  exit 1
fi

python3 - "$REPO_ROOT/version.json" "$VERSION" <<'PY'
import json, sys
path, version = sys.argv[1], sys.argv[2]
data = json.load(open(path))
for platform in ("ios", "macos"):
    data[platform]["version"] = version
with open(path, "w") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write("\n")
PY

bash "$REPO_ROOT/scripts/sync_version.sh"
echo "version.json 已更新为 $VERSION"
