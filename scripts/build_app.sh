#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="ASIAIRSync"
BUILD_DIR="${ROOT_DIR}/build"
APP_DIR="${BUILD_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

VERSION="${VERSION:-0.1.0}"
BUNDLE_ID="${BUNDLE_ID:-com.serhiiboreiko.asiairsync}"

mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

swiftc \
  -O \
  -parse-as-library \
  "${ROOT_DIR}/App/ASIAIRSyncApp.swift" \
  "${ROOT_DIR}/App/AppModel.swift" \
  "${ROOT_DIR}/App/MenuBarContentView.swift" \
  "${ROOT_DIR}/App/Models.swift" \
  "${ROOT_DIR}/App/StartAtLoginManager.swift" \
  "${ROOT_DIR}/App/UpdateChecker.swift" \
  "${ROOT_DIR}/App/SyncEngine.swift" \
  -framework SwiftUI \
  -framework AppKit \
  -framework ServiceManagement \
  -o "${MACOS_DIR}/${APP_NAME}"

cat > "${CONTENTS_DIR}/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>${APP_NAME}</string>
  <key>CFBundleIdentifier</key>
  <string>${BUNDLE_ID}</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleIconFile</key>
  <string>${APP_NAME}</string>
  <key>CFBundleName</key>
  <string>${APP_NAME}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
</dict>
</plist>
PLIST

if [[ -f "${ROOT_DIR}/assets/${APP_NAME}.icns" ]]; then
  cp "${ROOT_DIR}/assets/${APP_NAME}.icns" "${RESOURCES_DIR}/${APP_NAME}.icns"
else
  echo "Warning: icon file not found at ${ROOT_DIR}/assets/${APP_NAME}.icns"
fi

if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "${APP_DIR}" >/dev/null 2>&1 || true
fi

echo "Built app: ${APP_DIR}"
