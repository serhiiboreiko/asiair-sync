#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="ASIAIRSync"
VERSION="${VERSION:-0.1.0}"

"${ROOT_DIR}/scripts/build_app.sh"

APP_DIR="${ROOT_DIR}/build/${APP_NAME}.app"
DIST_DIR="${ROOT_DIR}/dist"
STAGING_DIR="${ROOT_DIR}/build/dmg-staging"
DMG_PATH="${DIST_DIR}/${APP_NAME}-${VERSION}.dmg"

rm -rf "${STAGING_DIR}"
mkdir -p "${DIST_DIR}" "${STAGING_DIR}"

cp -R "${APP_DIR}" "${STAGING_DIR}/"
ln -s /Applications "${STAGING_DIR}/Applications"

hdiutil create \
  -volname "${APP_NAME}" \
  -srcfolder "${STAGING_DIR}" \
  -ov \
  -format UDZO \
  "${DMG_PATH}" >/dev/null

echo "Built dmg: ${DMG_PATH}"
