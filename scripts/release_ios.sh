#!/bin/bash
# release_ios.sh — 构建未签名 iOS IPA
# 用法：./scripts/release_ios.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_DIR="$REPO_ROOT/app"
DIST_DIR="$REPO_ROOT/dist"
BUILD_DIR="$REPO_ROOT/.build-release"
VERSION_FILE="$REPO_ROOT/version.json"
SCHEME="Tube-iOS"

# ── 前置检查 ──
if ! command -v xcodegen &> /dev/null; then
  echo "error: xcodegen is required. Install: brew install xcodegen" >&2
  exit 1
fi

if ! command -v python3 &> /dev/null; then
  echo "error: python3 is required" >&2
  exit 1
fi

if [[ ! -f "$VERSION_FILE" ]]; then
  echo "error: version.json not found at $VERSION_FILE" >&2
  exit 1
fi

# ── 读取版本号 ──
VERSION=$(python3 -c "import json; print(json.load(open('$VERSION_FILE'))['ios']['version'])")
BUILD_NUMBER=$(python3 -c "import json; print(json.load(open('$VERSION_FILE'))['ios']['build'])")

echo "==> Tube iOS v${VERSION} (build ${BUILD_NUMBER})"

# ── 同步版本 & 生成工程 ──
"$REPO_ROOT/scripts/sync_version.sh"

echo "==> Generating Xcode project..."
(cd "$PROJECT_DIR" && xcodegen generate --quiet)

# ── 准备目录 ──
rm -rf "$BUILD_DIR"
mkdir -p "$DIST_DIR" "$BUILD_DIR"

# ── Archive（未签名） ──
ARCHIVE_PATH="$BUILD_DIR/Tube-iOS.xcarchive"

echo ""
echo "==> Archiving (unsigned)..."

xcodebuild archive \
  -project "$PROJECT_DIR/Tube.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  -destination "generic/platform=iOS" \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  -quiet

# ── 打包 IPA ──
IPA_NAME="Tube-v${VERSION}-ios-unsigned.ipa"
PAYLOAD_DIR="$BUILD_DIR/Payload"

echo "==> Packaging IPA..."

mkdir -p "$PAYLOAD_DIR"
cp -R "$ARCHIVE_PATH/Products/Applications/"*.app "$PAYLOAD_DIR/"

(cd "$BUILD_DIR" && zip -r -q "$DIST_DIR/$IPA_NAME" Payload/)

echo "  -> $IPA_NAME"

# ── 清理 ──
rm -rf "$BUILD_DIR"

echo ""
echo "==> Done! Output:"
ls -lh "$DIST_DIR/$IPA_NAME"
