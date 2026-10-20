#!/bin/bash
set -euo pipefail
PROJECT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$PROJECT/Info.plist")"
OUT="${1:-$PROJECT/Builds/Release-$VERSION}"
mkdir -p "$OUT/Reports"
OUT="$(cd "$OUT" && pwd)"
if [[ "$OUT" == "$PROJECT" || ( "$OUT" == "$PROJECT/"* && "$OUT" != "$PROJECT/Builds/"* ) ]]; then
  echo "Use Builds/<version> or a directory outside the source project." >&2; exit 1
fi
cd "$PROJECT"
SCRATCH="$OUT/BuildCache"
SDK="$(xcrun --sdk macosx --show-sdk-version)"
# SwiftPM's swiftbuild backend can otherwise record the deployment target as SDK.
# Keep macOS 14 compatibility while opting in to the selected SDK's native design.
FLAGS=(-Xlinker -platform_version -Xlinker macos -Xlinker 14.0 -Xlinker "$SDK")
xcodebuild -version > "$OUT/Reports/toolchain.txt"
swift --version >> "$OUT/Reports/toolchain.txt"
SMOOTHQUIT_SNAPSHOT_DIR="$OUT/Reports/Interface" swift test "${FLAGS[@]}" --scratch-path "$SCRATCH" > "$OUT/Reports/tests.log" 2>&1
swift build "${FLAGS[@]}" -c release --arch arm64 --arch x86_64 --scratch-path "$SCRATCH" > "$OUT/Reports/build.log" 2>&1
BIN="$(swift build -c release --arch arm64 --arch x86_64 --scratch-path "$SCRATCH" --show-bin-path)"
STAGE="$(mktemp -d "$OUT/.packaging.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
APP="$STAGE/SmoothQuit.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$STAGE/icon-work"
cp "$BIN/SmoothQuit" "$APP/Contents/MacOS/SmoothQuit"
cp "$PROJECT/Info.plist" "$APP/Contents/Info.plist"
ditto "$BIN/SmoothQuit_SmoothQuit.bundle" "$APP/Contents/Resources/SmoothQuit_SmoothQuit.bundle"
# Icon Composer supplies the system-rendered icon plus an .icns fallback for older macOS.
xcrun actool "$PROJECT/Assets/AppIcon.icon" --compile "$APP/Contents/Resources" \
  --platform macosx --target-device mac --minimum-deployment-target 14.0 \
  --app-icon AppIcon --output-partial-info-plist "$STAGE/icon-work/partial.plist" \
  > "$OUT/Reports/icon.txt" 2>&1
rm -rf "$STAGE/icon-work"
codesign --force --sign - --options runtime --timestamp=none "$APP"
codesign --verify --deep --strict --verbose=2 "$APP" > "$OUT/Reports/signature.txt" 2>&1
codesign -d --verbose=4 "$APP" >> "$OUT/Reports/signature.txt" 2>&1
file "$APP/Contents/MacOS/SmoothQuit" > "$OUT/Reports/binary.txt"
xcrun vtool -show-build "$APP/Contents/MacOS/SmoothQuit" >> "$OUT/Reports/binary.txt"
plutil -lint "$APP/Contents/Info.plist" >> "$OUT/Reports/binary.txt"
ditto "$APP" "$OUT/SmoothQuit.app"
ln -s /Applications "$STAGE/Applications"
cp "$PROJECT/README.md" "$PROJECT/LICENSE" "$STAGE/"
ditto "$PROJECT/docs" "$STAGE/docs"
hdiutil create -volname SmoothQuit -srcfolder "$STAGE" -ov -format UDZO "$OUT/SmoothQuit.dmg"
hdiutil verify "$OUT/SmoothQuit.dmg" > "$OUT/Reports/dmg.txt" 2>&1
mkdir -p "$OUT/Source"
rsync -a --exclude 'Builds' --exclude '.build' --exclude '.git' --exclude '.swiftpm' --exclude '.DS_Store' "$PROJECT/" "$OUT/Source/"
(cd "$OUT" && shasum -a 256 SmoothQuit.dmg SmoothQuit.app/Contents/MacOS/SmoothQuit) > "$OUT/Reports/SHA256.txt"
echo "Built: $OUT/SmoothQuit.app"
echo "Built: $OUT/SmoothQuit.dmg"
