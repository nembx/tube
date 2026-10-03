#!/bin/bash
# release_macos.sh — 构建 macOS DMG（arm64 / x86_64 / universal）
# 用法：./scripts/release_macos.sh [--arch arm64|x86_64|universal]
#       不指定 --arch 则构建全部三个架构
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_DIR="$REPO_ROOT/app"
DIST_DIR="$REPO_ROOT/dist"
BUILD_DIR="$REPO_ROOT/.build-release"
VERSION_FILE="$REPO_ROOT/version.json"
SCHEME="Tube-macOS"

# ── 参数解析 ──
REQUESTED_ARCH=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --arch)
      REQUESTED_ARCH="$2"
      shift 2
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      echo "usage: $0 [--arch arm64|x86_64|universal]" >&2
      exit 1
      ;;
  esac
done

if [[ -n "$REQUESTED_ARCH" ]] && [[ "$REQUESTED_ARCH" != "arm64" && "$REQUESTED_ARCH" != "x86_64" && "$REQUESTED_ARCH" != "universal" ]]; then
  echo "error: --arch must be arm64, x86_64, or universal" >&2
  exit 1
fi

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
VERSION=$(python3 -c "import json; print(json.load(open('$VERSION_FILE'))['macos']['version'])")
BUILD_NUMBER=$(python3 -c "import json; print(json.load(open('$VERSION_FILE'))['macos']['build'])")

echo "==> Tube macOS v${VERSION} (build ${BUILD_NUMBER})"

# ── 同步版本 & 生成工程 ──
"$REPO_ROOT/scripts/sync_version.sh"

echo "==> Generating Xcode project..."
(cd "$PROJECT_DIR" && xcodegen generate --quiet)

# ── 准备目录 ──
rm -rf "$BUILD_DIR"
mkdir -p "$DIST_DIR" "$BUILD_DIR"

# ── 构建单个架构 ──
build_variant() {
  local LABEL="$1"    # arm64 | x86_64 | universal
  local ARCHS="$2"    # 传给 ARCHS= 的值

  echo ""
  echo "==> Building $LABEL ($ARCHS)..."

  local ARCHIVE_PATH="$BUILD_DIR/Tube-macOS-${LABEL}.xcarchive"
  local APP_STAGE="$BUILD_DIR/$LABEL"
  local DMG_NAME="Tube-v${VERSION}-macos-${LABEL}.dmg"

  # Archive
  xcodebuild archive \
    -project "$PROJECT_DIR/Tube.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    -destination "generic/platform=macOS" \
    ARCHS="$ARCHS" \
    ONLY_ACTIVE_ARCH=NO \
    CODE_SIGN_IDENTITY="-" \
    -quiet

  # 从 archive 提取 .app
  mkdir -p "$APP_STAGE"
  cp -R "$ARCHIVE_PATH/Products/Applications/"*.app "$APP_STAGE/"
  ln -s /Applications "$APP_STAGE/Applications"

  # Ad-hoc codesign（确保 entitlements 生效）
  codesign --force --deep --sign - "$APP_STAGE/"*.app

  # 打包 DMG
  hdiutil create \
    -volname "Tube" \
    -srcfolder "$APP_STAGE" \
    -ov -format UDZO \
    "$DIST_DIR/$DMG_NAME" \
    -quiet

  rm -rf "$ARCHIVE_PATH" "$APP_STAGE"

  echo "  -> $DMG_NAME"
}

# ── 执行构建 ──
if [[ -z "$REQUESTED_ARCH" ]]; then
  # 默认：构建全部三个
  build_variant "arm64"     "arm64"
  build_variant "x86_64"    "x86_64"
  build_variant "universal"  "arm64 x86_64"
else
  case "$REQUESTED_ARCH" in
    arm64)     build_variant "arm64"     "arm64" ;;
    x86_64)    build_variant "x86_64"    "x86_64" ;;
    universal) build_variant "universal"  "arm64 x86_64" ;;
  esac
fi

# ── 清理 ──
rm -rf "$BUILD_DIR"

echo ""
echo "==> Done! Output:"
ls -lh "$DIST_DIR"/Tube-*-macos-*.dmg 2>/dev/null || true
