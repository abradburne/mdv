#!/bin/sh
set -euo pipefail

APP_NAME="mdv"
BUNDLE_ID="jp.co.xenocode.mdv"
VERSION="0.1"
MIN_MACOS="12.0"
TEAM_ID="HVUXZ635F3"
SIGN_ID="Developer ID Application: XenoCode Inc (HVUXZ635F3)"
NOTARY_PROFILE="mdv-notary"
APPLE_ID="alan@xenocode.co.jp"

BUILD_DIR=".build/release"
APP_BUNDLE="${APP_NAME}.app"
DMG="${APP_NAME}.dmg"
DMG_RW="${APP_NAME}-rw.dmg"
MOUNT_POINT="/Volumes/${APP_NAME}"
ASSET_CATALOG="Sources/mdv/Resources/AppIcon.xcassets"

log() {
  echo "==> $*"
}

create_info_plist() {
  cat > "${APP_BUNDLE}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
 "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>${APP_NAME}</string>
  <key>CFBundleDisplayName</key>
  <string>${APP_NAME}</string>
  <key>CFBundleIdentifier</key>
  <string>${BUNDLE_ID}</string>
  <key>CFBundleVersion</key>
  <string>${VERSION}</string>
  <key>CFBundleShortVersionString</key>
  <string>${VERSION}</string>
  <key>CFBundleExecutable</key>
  <string>${APP_NAME}</string>
  <key>CFBundleIconName</key>
  <string>AppIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>${MIN_MACOS}</string>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key>
      <string>Markdown File</string>
      <key>CFBundleTypeRole</key>
      <string>Viewer</string>
      <key>LSHandlerRank</key>
      <string>Alternate</string>
      <key>LSItemContentTypes</key>
      <array>
        <string>net.daringfireball.markdown</string>
      </array>
    </dict>
  </array>
</dict>
</plist>
PLIST
}

compile_assets() {
  if [ -d "${ASSET_CATALOG}" ]; then
    log "Compiling asset catalog"
    xcrun actool "${ASSET_CATALOG}" \
      --compile "${APP_BUNDLE}/Contents/Resources" \
      --platform macosx \
      --minimum-deployment-target "${MIN_MACOS}" \
      --app-icon "AppIcon" \
      --output-partial-info-plist "${BUILD_DIR}/asset-info.plist" >/dev/null
  fi
}

build_app_bundle() {
  log "Building release"
  swift build -c release

  log "Creating app bundle"
  rm -rf "${APP_BUNDLE}"
  mkdir -p "${APP_BUNDLE}/Contents/MacOS" "${APP_BUNDLE}/Contents/Resources"
  cp "${BUILD_DIR}/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
  cp -R "${BUILD_DIR}"/*.bundle "${APP_BUNDLE}/Contents/Resources/" 2>/dev/null || true

  compile_assets
  create_info_plist
}

sign_app() {
  log "Code signing app"
  codesign --force --options runtime --timestamp --sign "${SIGN_ID}" "${APP_BUNDLE}"
  codesign --verify --deep --strict --verbose=2 "${APP_BUNDLE}"
}

create_dmg() {
  log "Creating DMG with Applications link"
  hdiutil detach "${MOUNT_POINT}" >/dev/null 2>&1 || true
  hdiutil create -volname "${APP_NAME}" -srcfolder "${APP_BUNDLE}" -ov -format UDRW -fs HFS+ "${DMG_RW}" >/dev/null

  MOUNT_DIR=$(hdiutil attach -readwrite -noverify -noautoopen -nobrowse -mountpoint "${MOUNT_POINT}" "${DMG_RW}" | awk '/\/Volumes\// {print $3; exit}')
  if [ -z "${MOUNT_DIR}" ]; then
    echo "Failed to mount DMG at ${MOUNT_POINT}"
    exit 1
  fi

  ln -s /Applications "${MOUNT_DIR}/Applications"

  sync
  sleep 1
  if ! hdiutil detach "${MOUNT_DIR}" >/dev/null; then
    sleep 2
    if ! hdiutil detach -force "${MOUNT_DIR}" >/dev/null; then
      diskutil unmount force "${MOUNT_DIR}" >/dev/null 2>&1 || true
      diskutil eject "${MOUNT_DIR}" >/dev/null 2>&1 || true
    fi
  fi

  hdiutil convert "${DMG_RW}" -format UDZO -ov -o "${DMG}" >/dev/null
  rm -f "${DMG_RW}"
}

sign_and_notarize_dmg() {
  log "Signing DMG"
  codesign --force --timestamp --sign "${SIGN_ID}" "${DMG}"

  if ! xcrun notarytool history --keychain-profile "${NOTARY_PROFILE}" >/dev/null 2>&1; then
    echo "==> Notary profile missing. Create it with:"
    echo "xcrun notarytool store-credentials \"${NOTARY_PROFILE}\" \\\n  --apple-id \"${APPLE_ID}\" \\\n  --team-id \"${TEAM_ID}\" \\\n  --password \"app-specific-password\""
    exit 1
  fi

  log "Notarizing DMG"
  xcrun notarytool submit "${DMG}" --keychain-profile "${NOTARY_PROFILE}" --wait

  log "Stapling DMG"
  xcrun stapler staple "${DMG}"
}

build_app_bundle
sign_app
create_dmg
sign_and_notarize_dmg

log "Done: ${DMG}"
