#!/bin/bash
set -e

# CrateBot Notarization Script
# Usage: ./scripts/notarize.sh <path-to-app>
#
# Required environment variables:
# - APPLE_ID: Your Apple ID email
# - APPLE_TEAM_ID: Your team ID (10-character string)
# - APPLE_APP_PASSWORD: App-specific password from appleid.apple.com

APP_PATH="${1:?Usage: $0 <path-to-app>}"
APP_NAME=$(basename "$APP_PATH" .app)
BUNDLE_ID="com.cratebot.app"

# Verify environment
if [[ -z "$APPLE_ID" ]] || [[ -z "$APPLE_TEAM_ID" ]] || [[ -z "$APPLE_APP_PASSWORD" ]]; then
    echo "Error: Missing required environment variables"
    echo "  APPLE_ID: Apple ID email"
    echo "  APPLE_TEAM_ID: Team ID"
    echo "  APPLE_APP_PASSWORD: App-specific password"
    exit 1
fi

echo "=== CrateBot Notarization ==="
echo "App: $APP_PATH"
echo "Bundle ID: $BUNDLE_ID"

# Step 1: Create ZIP for notarization
echo ""
echo "Step 1: Creating ZIP archive..."
ZIP_PATH="/tmp/${APP_NAME}.zip"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
echo "Created: $ZIP_PATH"

# Step 2: Submit for notarization
echo ""
echo "Step 2: Submitting for notarization..."
SUBMIT_OUTPUT=$(xcrun notarytool submit "$ZIP_PATH" \
    --apple-id "$APPLE_ID" \
    --team-id "$APPLE_TEAM_ID" \
    --password "$APPLE_APP_PASSWORD" \
    --wait 2>&1)

echo "$SUBMIT_OUTPUT"

# Check if successful
if echo "$SUBMIT_OUTPUT" | grep -q "status: Accepted"; then
    echo ""
    echo "Step 3: Stapling ticket to app..."
    xcrun stapler staple "$APP_PATH"
    echo ""
    echo "=== Notarization Complete ==="
    echo "The app is now notarized and ready for distribution."
else
    echo ""
    echo "=== Notarization Failed ==="

    # Extract submission ID for log retrieval
    SUBMISSION_ID=$(echo "$SUBMIT_OUTPUT" | grep -o 'id: [a-f0-9-]*' | head -1 | cut -d' ' -f2)

    if [[ -n "$SUBMISSION_ID" ]]; then
        echo "Fetching notarization log..."
        xcrun notarytool log "$SUBMISSION_ID" \
            --apple-id "$APPLE_ID" \
            --team-id "$APPLE_TEAM_ID" \
            --password "$APPLE_APP_PASSWORD"
    fi

    exit 1
fi

# Cleanup
rm -f "$ZIP_PATH"
