#!/bin/bash
set -e

# CrateBot DMG Creator
# Usage: ./scripts/create-dmg.sh <path-to-app> [output-dir]

APP_PATH="${1:?Usage: $0 <path-to-app> [output-dir]}"
OUTPUT_DIR="${2:-build/release}"
APP_NAME=$(basename "$APP_PATH" .app)
VERSION=$(defaults read "$APP_PATH/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "1.0.0")
DMG_NAME="${APP_NAME}-${VERSION}"
DMG_PATH="${OUTPUT_DIR}/${DMG_NAME}.dmg"

echo "=== Creating CrateBot DMG ==="
echo "App: $APP_PATH"
echo "Version: $VERSION"
echo "Output: $DMG_PATH"

# Validate app exists
if [[ ! -d "$APP_PATH" ]]; then
    echo "Error: App not found at $APP_PATH"
    exit 1
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Check for create-dmg tool
if ! command -v create-dmg &> /dev/null; then
    echo "Installing create-dmg via Homebrew..."
    if ! command -v brew &> /dev/null; then
        echo "Error: Homebrew not installed. Install from https://brew.sh"
        exit 1
    fi
    brew install create-dmg
fi

# Remove existing DMG if present
rm -f "$DMG_PATH"

# Create DMG
echo ""
echo "Creating DMG..."

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKGROUND="${SCRIPT_DIR}/dmg-background.png"

# Build create-dmg command
DMG_ARGS=(
    --volname "CrateBot"
    --window-pos 200 120
    --window-size 600 400
    --icon-size 100
    --icon "CrateBot.app" 150 190
    --hide-extension "CrateBot.app"
    --app-drop-link 450 190
    --no-internet-enable
)

# Add volume icon if app icon exists
if [[ -f "$APP_PATH/Contents/Resources/AppIcon.icns" ]]; then
    DMG_ARGS+=(--volicon "$APP_PATH/Contents/Resources/AppIcon.icns")
fi

# Add background if exists
if [[ -f "$BACKGROUND" ]]; then
    DMG_ARGS+=(--background "$BACKGROUND")
fi

create-dmg "${DMG_ARGS[@]}" "$DMG_PATH" "$APP_PATH"

echo ""
echo "=== DMG Created ==="
echo "Output: $DMG_PATH"
echo "Size: $(du -h "$DMG_PATH" | cut -f1)"

# Notarize DMG if environment is set
if [[ -n "$APPLE_ID" ]] && [[ -n "$APPLE_TEAM_ID" ]] && [[ -n "$APPLE_APP_PASSWORD" ]]; then
    echo ""
    echo "Notarizing DMG..."
    xcrun notarytool submit "$DMG_PATH" \
        --apple-id "$APPLE_ID" \
        --team-id "$APPLE_TEAM_ID" \
        --password "$APPLE_APP_PASSWORD" \
        --wait

    xcrun stapler staple "$DMG_PATH"
    echo "DMG notarized and stapled."
else
    echo ""
    echo "Note: Set APPLE_ID, APPLE_TEAM_ID, and APPLE_APP_PASSWORD to auto-notarize the DMG."
fi
