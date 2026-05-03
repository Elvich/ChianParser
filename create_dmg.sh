#!/bin/bash

# Настройки
APP_NAME="ChianParser"
SCHEME="ChianParser"
BUILD_DIR="./build"
DMG_DIR="./dmg_temp"
DMG_NAME="ChianParser_Installer.dmg"

# 1. Очистка предыдущих сборок
echo "🧹 Cleaning up..."
rm -rf "$BUILD_DIR"
rm -rf "$DMG_DIR"
rm -f "$DMG_NAME"

# 2. Сборка приложения
echo "🏗️ Building app..."
xcodebuild -scheme "$SCHEME" \
           -configuration Release \
           -derivedDataPath "$BUILD_DIR" \
           -destination 'platform=macOS' \
           build

# Находим путь к собранному .app
APP_PATH=$(find "$BUILD_DIR" -name "$APP_NAME.app" -type d | head -n 1)

if [ -z "$APP_PATH" ]; then
    echo "❌ Error: App not found!"
    exit 1
fi

# 3. Подготовка папки для DMG
echo "📂 Preparing DMG content..."
mkdir -p "$DMG_DIR"
cp -R "$APP_PATH" "$DMG_DIR/"
ln -s /Applications "$DMG_DIR/Applications"

# 4. Создание DMG
echo "💿 Creating DMG..."
hdiutil create -volname "$APP_NAME" \
               -srcfolder "$DMG_DIR" \
               -ov -format UDZO \
               "$DMG_NAME"

# 5. Очистка временных файлов
echo "🧹 Final cleanup..."
rm -rf "$DMG_DIR"
rm -rf "$BUILD_DIR"

echo "✅ Success! Installer created: $DMG_NAME"
