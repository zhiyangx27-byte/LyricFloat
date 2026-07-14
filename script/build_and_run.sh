#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="LyricFloat"
BUNDLE_ID="com.trivia.LyricFloat"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="${LYRICFLOAT_DERIVED_DATA:-$ROOT_DIR/build/DerivedData}"
SWIFT_BUILD_DIR="${LYRICFLOAT_SWIFT_BUILD_DIR:-$ROOT_DIR/build/SwiftPM}"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE=""

select_xcode() {
  if xcodebuild -version >/dev/null 2>&1; then
    return 0
  fi

  local xcode_app
  xcode_app="$({
    find /Applications -maxdepth 1 -type d -name 'Xcode*.app' -print 2>/dev/null
    if [[ -d "$HOME/Applications" ]]; then
      find "$HOME/Applications" -maxdepth 1 -type d -name 'Xcode*.app' -print 2>/dev/null
    fi
  } | sort -V | tail -n 1)"

  if [[ -n "$xcode_app" && -d "$xcode_app/Contents/Developer" ]]; then
    export DEVELOPER_DIR="$xcode_app/Contents/Developer"
  fi

  xcodebuild -version >/dev/null 2>&1
}

sdk_path() {
  xcrun --sdk macosx --show-sdk-path 2>/dev/null
}

run_tests() {
  local sdk
  if ! select_xcode; then
    echo "Running tests requires a full Xcode installation." >&2
    return 1
  fi
  sdk="$(sdk_path)"
  SDKROOT="$sdk" swift test --scratch-path "$SWIFT_BUILD_DIR"
}

build_with_xcode() {
  local configuration="$1"
  local destination
  local -a architecture_settings

  if [[ "$configuration" == "Release" ]]; then
    destination="generic/platform=macOS"
    architecture_settings=(ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO)
  else
    destination="platform=macOS,arch=$(uname -m)"
    architecture_settings=(ONLY_ACTIVE_ARCH=YES)
  fi

  xcodebuild \
    -project "$ROOT_DIR/LyricFloat.xcodeproj" \
    -scheme "$APP_NAME" \
    -configuration "$configuration" \
    -destination "$destination" \
    -derivedDataPath "$DERIVED_DATA" \
    "${architecture_settings[@]}" \
    build

  APP_BUNDLE="$DERIVED_DATA/Build/Products/$configuration/$APP_NAME.app"
}

build_with_swiftpm() {
  local configuration="$1"
  local swift_configuration
  local sdk
  local binary_directory
  local contents

  swift_configuration="$(printf '%s' "$configuration" | tr '[:upper:]' '[:lower:]')"
  sdk="$(sdk_path)"
  echo "Full Xcode not found; building the current Mac architecture with SwiftPM." >&2

  SDKROOT="$sdk" swift build \
    --configuration "$swift_configuration" \
    --scratch-path "$SWIFT_BUILD_DIR" \
    --disable-sandbox
  binary_directory="$(SDKROOT="$sdk" swift build \
    --configuration "$swift_configuration" \
    --scratch-path "$SWIFT_BUILD_DIR" \
    --show-bin-path)"

  APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
  contents="$APP_BUNDLE/Contents"
  rm -rf "$APP_BUNDLE"
  mkdir -p "$contents/MacOS" "$contents/Resources"
  cp "$binary_directory/$APP_NAME" "$contents/MacOS/$APP_NAME"
  cp "$ROOT_DIR/Resources/Info.plist" "$contents/Info.plist"
  cp "$ROOT_DIR/Resources/LyricFloat.icns" "$contents/Resources/LyricFloat.icns"
  for localization_dir in "$ROOT_DIR"/Resources/*.lproj; do
    [[ -d "$localization_dir" ]] || continue
    ditto "$localization_dir" "$contents/Resources/$(basename "$localization_dir")"
  done
  /usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $APP_NAME" "$contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleName $APP_NAME" "$contents/Info.plist"
  codesign \
    --force \
    --deep \
    --options runtime \
    --sign - \
    --entitlements "$ROOT_DIR/Resources/LyricFloat.entitlements" \
    "$APP_BUNDLE"
}

build_app() {
  local configuration="$1"
  if select_xcode; then
    build_with_xcode "$configuration"
  else
    build_with_swiftpm "$configuration"
  fi
}

open_app() {
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  test|--test)
    run_tests
    exit 0
    ;;
  release|--release|install|--install)
    CONFIGURATION="Release"
    ;;
  run|build|--build|debug|--debug|logs|--logs|telemetry|--telemetry|verify|--verify)
    CONFIGURATION="Debug"
    ;;
  *)
    echo "usage: $0 [run|build|test|release|install|debug|logs|telemetry|verify]" >&2
    exit 2
    ;;
esac

build_app "$CONFIGURATION"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"

case "$MODE" in
  run)
    open_app
    ;;
  build|--build|release|--release)
    echo "$APP_BUNDLE"
    ;;
  install|--install)
    INSTALL_DIR="${LYRICFLOAT_INSTALL_DIR:-/Applications}"
    INSTALLED_APP="$INSTALL_DIR/$APP_NAME.app"
    pkill -x "$APP_NAME" >/dev/null 2>&1 || true
    mkdir -p "$INSTALL_DIR"
    rm -rf "$INSTALLED_APP"
    ditto "$APP_BUNDLE" "$INSTALLED_APP"
    /System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister \
      -f "$INSTALLED_APP"
    /usr/bin/open -n "$INSTALLED_APP"
    echo "$INSTALLED_APP"
    ;;
  debug|--debug)
    pkill -x "$APP_NAME" >/dev/null 2>&1 || true
    lldb -- "$APP_BINARY"
    ;;
  logs|--logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  telemetry|--telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  verify|--verify)
    open_app
    sleep 2
    pgrep -x "$APP_NAME" >/dev/null
    ;;
esac
