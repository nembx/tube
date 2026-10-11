#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
XCODEGEN="${XCODEGEN:-xcodegen}"
MODE="${1:-macos}"
case "$MODE" in
  project|macos|ios|simulator|test) ;;
  *) echo "Usage: $0 [project|macos|ios|simulator|test]" >&2; exit 1 ;;
esac

bash "$ROOT/scripts/sync_version.sh"
bash "$ROOT/app/scripts/sync_seed_rules.sh"
if [[ "$MODE" == test ]]; then
  exec swift test --package-path "$ROOT/app/TubeKit"
fi
"$XCODEGEN" generate --spec "$ROOT/app/project.yml"
[[ "$MODE" == project ]] && exit 0

case "$MODE" in
  macos) SCHEME=Tube-macOS; DESTINATION='platform=macOS'; CONFIG=Release ;;
  ios) SCHEME=Tube-iOS; DESTINATION='generic/platform=iOS'; CONFIG=Release ;;
  simulator) SCHEME=Tube-iOS; DESTINATION='generic/platform=iOS Simulator'; CONFIG=Debug ;;
esac

xcodebuild build -project "$ROOT/app/Tube.xcodeproj" -scheme "$SCHEME" \
  -configuration "$CONFIG" -destination "$DESTINATION" \
  -derivedDataPath "$ROOT/artifacts/$MODE" \
  CODE_SIGNING_ALLOWED=NO -quiet

if [[ "$MODE" == macos ]]; then
  APP="$ROOT/artifacts/macos/Build/Products/Release/Tube.app"
  codesign --force --deep --sign - --entitlements "$ROOT/app/Tube-macOS/Tube_macOS.entitlements" "$APP"
  echo "Built: $APP (local ad-hoc signature)"
elif [[ "$MODE" == ios ]]; then
  STAGE=$(mktemp -d "$ROOT/artifacts/ios/ipa.XXXXXX")
  mkdir "$STAGE/Payload"
  ditto "$ROOT/artifacts/ios/Build/Products/Release-iphoneos/Tube.app" "$STAGE/Payload/Tube.app"
  ditto -c -k --keepParent "$STAGE/Payload" "$ROOT/artifacts/Tube-ios-unsigned.ipa"
  echo "Built: $ROOT/artifacts/Tube-ios-unsigned.ipa (requires signing before installation)"
else
  echo "Built: $ROOT/artifacts/simulator/Build/Products/Debug-iphonesimulator/Tube.app"
fi
