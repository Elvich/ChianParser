#!/bin/bash
set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
APP_NAME="ChianParser"
SCHEME="ChianParser"
BUILD_DIR="./build"
DMG_STAGING="./dmg_temp"

# Paths relative to this script's location (App/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PRIVATE_KEY_FILE="$REPO_ROOT/.sparkle_private_key"

cd "$SCRIPT_DIR"

# ---------------------------------------------------------------------------
# Step 1: Extract version from built app's Info.plist
# ---------------------------------------------------------------------------
echo "🏗️  Building $APP_NAME..."
xcodebuild -scheme "$SCHEME" \
           -configuration Release \
           -derivedDataPath "$BUILD_DIR" \
           -destination 'platform=macOS' \
           CODE_SIGN_IDENTITY="-" \
           build \
           | xcpretty 2>/dev/null || true   # xcpretty is optional

APP_PATH=$(find "$BUILD_DIR" -name "$APP_NAME.app" -type d | head -n 1)
if [ -z "$APP_PATH" ]; then
    echo "❌ Build failed: $APP_NAME.app not found in $BUILD_DIR"
    exit 1
fi

INFO_PLIST="$APP_PATH/Contents/Info.plist"
SHORT_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST")
BUILD_NUMBER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$INFO_PLIST")

if [ -z "$SHORT_VERSION" ] || [ -z "$BUILD_NUMBER" ]; then
    echo "❌ Failed to read version from $INFO_PLIST"
    exit 1
fi

DMG_NAME="${APP_NAME}_${SHORT_VERSION}_b${BUILD_NUMBER}.dmg"
echo "📦 Version: $SHORT_VERSION (build $BUILD_NUMBER) → $DMG_NAME"

# ---------------------------------------------------------------------------
# Step 2: Clean up any previous artifact with this name
# ---------------------------------------------------------------------------
rm -rf "$DMG_STAGING"
rm -f "$DMG_NAME"

# ---------------------------------------------------------------------------
# Step 3: Assemble DMG contents
# ---------------------------------------------------------------------------
echo "📂 Preparing DMG contents..."
mkdir -p "$DMG_STAGING"
cp -R "$APP_PATH" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

# ---------------------------------------------------------------------------
# Step 4: Create DMG
# ---------------------------------------------------------------------------
echo "💿 Creating $DMG_NAME..."
hdiutil create -volname "$APP_NAME" \
               -srcfolder "$DMG_STAGING" \
               -ov -format UDZO \
               "$DMG_NAME"

rm -rf "$DMG_STAGING"
rm -rf "$BUILD_DIR"

# ---------------------------------------------------------------------------
# Step 5: Sign with Sparkle (sign_update)
# ---------------------------------------------------------------------------
echo "🔏 Signing with Sparkle EdDSA..."

SIGN_UPDATE=$(find ~/Library/Developer/Xcode/DerivedData \
    -path "*/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update" \
    -type f 2>/dev/null | head -n 1)

if [ -z "$SIGN_UPDATE" ]; then
    echo "⚠️  sign_update not found in DerivedData — build the project in Xcode first."
    echo "   DMG created without signature: $SCRIPT_DIR/$DMG_NAME"
    exit 0
fi

if [ ! -f "$PRIVATE_KEY_FILE" ]; then
    echo "⚠️  Private key not found at $PRIVATE_KEY_FILE"
    echo "   Run: generate_keys -x .sparkle_private_key"
    echo "   DMG created without signature: $SCRIPT_DIR/$DMG_NAME"
    exit 0
fi

SIGN_OUTPUT=$("$SIGN_UPDATE" "$SCRIPT_DIR/$DMG_NAME" -f "$PRIVATE_KEY_FILE" 2>&1)

# sign_update output example:
#   sparkle:edSignature="ABC123..." sparkle:length="1234567"
ED_SIGNATURE=$(echo "$SIGN_OUTPUT" | grep -oE 'sparkle:edSignature="[^"]+"' | sed 's/sparkle:edSignature="//' | tr -d '"')
DMG_LENGTH=$(echo "$SIGN_OUTPUT"   | grep -oE 'sparkle:length="[^"]+"'      | sed 's/sparkle:length="//'      | tr -d '"')

if [ -z "$ED_SIGNATURE" ] || [ -z "$DMG_LENGTH" ]; then
    echo "❌ sign_update failed or produced unexpected output:"
    echo "$SIGN_OUTPUT"
    exit 1
fi

# ---------------------------------------------------------------------------
# Step 5.5: Write latest.json manifest for auto-updates
# ---------------------------------------------------------------------------
echo "📝 Writing latest.json manifest..."
cat <<EOF > "$SCRIPT_DIR/latest.json"
{
  "version": "$SHORT_VERSION",
  "build": "$BUILD_NUMBER",
  "length": "$DMG_LENGTH",
  "edSignature": "$ED_SIGNATURE",
  "dmg_name": "$DMG_NAME"
}
EOF

# ---------------------------------------------------------------------------
# Step 6: Print developer cheatsheet
# ---------------------------------------------------------------------------
GREEN='\033[0;32m'
BOLD='\033[1m'
RESET='\033[0m'

echo ""
echo -e "${GREEN}${BOLD}✅ Done! Copy these values into Backend/api/routes/appcast.py:${RESET}"
echo ""
echo -e "${GREEN}  edSignature  = \"${ED_SIGNATURE}\"${RESET}"
echo -e "${GREEN}  length       = \"${DMG_LENGTH}\"${RESET}"
echo -e "${GREEN}  version      = \"${BUILD_NUMBER}\"          # sparkle:version (build number)${RESET}"
echo -e "${GREEN}  short_version= \"${SHORT_VERSION}\"         # sparkle:shortVersionString${RESET}"
echo -e "${GREEN}  dmg          = ${DMG_NAME}${RESET}"
echo ""
