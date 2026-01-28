# CrateBot Distribution Guide

## Prerequisites

1. **Apple Developer Account** with Developer ID certificate
2. **Xcode 15+** installed
3. **App-specific password** from [appleid.apple.com](https://appleid.apple.com)

## Build Process

### 1. Build the App

```bash
# Build release configuration
xcodebuild -scheme CrateBot -configuration Release archive \
    -archivePath build/CrateBot.xcarchive

# Export for distribution
xcodebuild -exportArchive \
    -archivePath build/CrateBot.xcarchive \
    -exportPath build/release \
    -exportOptionsPlist ExportOptions.plist
```

### 2. Code Sign

The app should be signed during the build process with your Developer ID certificate.

Verify signing:
```bash
codesign -dv --verbose=4 build/release/CrateBot.app
```

### 3. Notarize

Set environment variables:
```bash
export APPLE_ID="your@email.com"
export APPLE_TEAM_ID="ABCD123456"
export APPLE_APP_PASSWORD="xxxx-xxxx-xxxx-xxxx"
```

Run notarization:
```bash
./scripts/notarize.sh build/release/CrateBot.app
```

### 4. Create DMG

```bash
./scripts/create-dmg.sh build/release/CrateBot.app
```

## Sparkle Auto-Updates

The app uses Sparkle 2.x for auto-updates.

### Appcast

Updates are published via an appcast XML file hosted at:
```
https://cratebot.app/appcast.xml
```

## Troubleshooting

### "App is damaged" error

The app may not be properly stapled. Run:
```bash
xcrun stapler staple CrateBot.app
```

### Gatekeeper rejection

Check notarization status:
```bash
spctl -a -vv CrateBot.app
```

### Code signing issues

Verify entitlements:
```bash
codesign -d --entitlements - CrateBot.app
```
