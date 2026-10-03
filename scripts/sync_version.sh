#!/bin/bash
# sync_version.sh — 从 version.json 生成 Xcode 使用的 xcconfig 文件
# 用法：./scripts/sync_version.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION_FILE="$REPO_ROOT/version.json"

if [[ ! -f "$VERSION_FILE" ]]; then
  echo "error: version.json not found at $VERSION_FILE" >&2
  exit 1
fi

if ! command -v python3 &> /dev/null; then
  echo "error: python3 is required but not found" >&2
  exit 1
fi

# 读取版本号
IOS_VERSION=$(python3 -c "import json; print(json.load(open('$VERSION_FILE'))['ios']['version'])")
IOS_BUILD=$(python3 -c "import json; print(json.load(open('$VERSION_FILE'))['ios']['build'])")
MACOS_VERSION=$(python3 -c "import json; print(json.load(open('$VERSION_FILE'))['macos']['version'])")
MACOS_BUILD=$(python3 -c "import json; print(json.load(open('$VERSION_FILE'))['macos']['build'])")

# 生成 xcconfig
cat > "$REPO_ROOT/app/Version-iOS.xcconfig" << EOF
// Auto-generated from version.json — do not edit manually
// Run scripts/sync_version.sh to regenerate
MARKETING_VERSION = $IOS_VERSION
CURRENT_PROJECT_VERSION = $IOS_BUILD
EOF

cat > "$REPO_ROOT/app/Version-macOS.xcconfig" << EOF
// Auto-generated from version.json — do not edit manually
// Run scripts/sync_version.sh to regenerate
MARKETING_VERSION = $MACOS_VERSION
CURRENT_PROJECT_VERSION = $MACOS_BUILD
EOF

echo "Synced versions from version.json:"
echo "  iOS:   $IOS_VERSION ($IOS_BUILD)"
echo "  macOS: $MACOS_VERSION ($MACOS_BUILD)"
