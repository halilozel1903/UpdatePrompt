#!/usr/bin/env bash
# Captures README screenshots of the example app on an iOS Simulator.
# Usage: scripts/screenshots.sh <Scheme> <bundle id> <scene> [<scene> ...]
set -euo pipefail

SCHEME="$1"; BUNDLE_ID="$2"; shift 2
OUT="docs/screenshots"
mkdir -p "$OUT"

# Newest available iPhone "Pro" simulator, falling back to any iPhone.
UDID=$(xcrun simctl list devices available -j | jq -r '
  [.devices | to_entries[] | select(.key | test("iOS")) | .value[] | select(.name | test("^iPhone"))]
  | (map(select(.name | test("Pro$"))) + .) | .[0].udid')
echo "Using simulator $UDID"

xcodebuild build \
  -project "Example/$SCHEME.xcodeproj" \
  -scheme "$SCHEME" \
  -destination "id=$UDID" \
  -derivedDataPath build \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM= | tail -n 5

APP=$(find build/Build/Products -name "$SCHEME.app" -maxdepth 2 | head -n 1)

xcrun simctl boot "$UDID" || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3
xcrun simctl install "$UDID" "$APP"

for appearance in light dark; do
  xcrun simctl ui "$UDID" appearance "$appearance"
  for scene in "$@"; do
    # A blank frame (app still launching after an appearance switch) compresses to a tiny PNG:
    # retry until the capture has real content.
    for attempt in 1 2 3; do
      xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
      sleep 1
      xcrun simctl launch "$UDID" "$BUNDLE_ID" -screenshot "$scene"
      sleep $((6 + attempt * 2))
      xcrun simctl io "$UDID" screenshot "$OUT/$scene-$appearance.png"
      [ "$(wc -c < "$OUT/$scene-$appearance.png")" -gt 100000 ] && break
      echo "Blank capture for $scene-$appearance, retrying"
    done
    if [ "$(wc -c < "$OUT/$scene-$appearance.png")" -le 100000 ]; then
      echo "Capture for $scene-$appearance is still blank; refusing to commit a broken screenshot." >&2
      exit 1
    fi
    echo "Captured $scene-$appearance"
  done
done
