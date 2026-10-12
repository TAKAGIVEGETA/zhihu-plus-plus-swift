#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_PATH="$IOS_DIR/iosApp.xcodeproj"
SCHEME="${SCHEME:-iosApp}"
BUNDLE_ID="${BUNDLE_ID:-com.github.kangyun1994.zhplus.swift}"

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

warn() {
  printf 'warning: %s\n' "$*" >&2
}

info() {
  printf '%s\n' "$*"
}

command -v xcode-select >/dev/null 2>&1 || fail "xcode-select is not available"
command -v xcodebuild >/dev/null 2>&1 || fail "xcodebuild is not available"
command -v xcrun >/dev/null 2>&1 || fail "xcrun is not available"
command -v plutil >/dev/null 2>&1 || fail "plutil is not available"
command -v xmllint >/dev/null 2>&1 || fail "xmllint is not available"

DEVELOPER_DIR_SELECTED="$(xcode-select -p 2>/dev/null || true)"
if [[ -z "$DEVELOPER_DIR_SELECTED" ]]; then
  fail "no Xcode developer directory is selected"
fi

case "$DEVELOPER_DIR_SELECTED" in
  *Xcode*.app/Contents/Developer) ;;
  *)
    fail "xcode-select points to '$DEVELOPER_DIR_SELECTED'. Select full Xcode with: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
    ;;
esac

XCODEBUILD_VERSION_OUTPUT="$(xcodebuild -version 2>&1)" || {
  case "$XCODEBUILD_VERSION_OUTPUT" in
    *license*)
      fail "Xcode license is not accepted. Run: sudo xcodebuild -license accept && sudo xcodebuild -runFirstLaunch"
      ;;
    *)
      fail "xcodebuild cannot run; open Xcode once and complete first launch if needed"
      ;;
  esac
}

IPHONEOS_SDK_OUTPUT="$(xcrun --sdk iphoneos --show-sdk-path 2>&1)" || {
  case "$IPHONEOS_SDK_OUTPUT" in
    *license*)
      fail "Xcode license is not accepted. Run: sudo xcodebuild -license accept && sudo xcodebuild -runFirstLaunch"
      ;;
    *)
      fail "iphoneos SDK is not available from the selected Xcode"
      ;;
  esac
}

SIMCTL_OUTPUT="$(xcrun simctl list runtimes 2>&1)" || {
  case "$SIMCTL_OUTPUT" in
    *license*)
      fail "Xcode license is not accepted. Run: sudo xcodebuild -license accept && sudo xcodebuild -runFirstLaunch"
      ;;
    *)
      warn "simctl is not available; simulator testing may fail"
      ;;
  esac
}

[[ -d "$PROJECT_PATH" ]] || fail "missing Xcode project at $PROJECT_PATH"
[[ -f "$IOS_DIR/iosApp/Info.plist" ]] || fail "missing iosApp/Info.plist"

plutil -lint "$IOS_DIR/iosApp/Info.plist" >/dev/null
plutil -lint "$PROJECT_PATH/project.pbxproj" >/dev/null
xmllint --noout "$IOS_DIR/iosApp/LaunchScreen.storyboard"

if [[ -z "${TEAM_ID:-}" && -z "${SKIP_TEAM_ID_WARNING:-}" ]]; then
  warn "TEAM_ID is not set. Xcode can still use a team chosen in Signing & Capabilities; CLI builds may need TEAM_ID=<YOUR_TEAM_ID>."
fi

if [[ -n "${DEVICE_ID:-}" ]]; then
  DESTINATION="platform=iOS,id=$DEVICE_ID"
  DESTINATION_MATCH="id:$DEVICE_ID"
else
  DESTINATION="generic/platform=iOS"
  DESTINATION_MATCH="name:Any iOS Device"
fi

DESTINATIONS_OUTPUT="$(xcodebuild -project "$PROJECT_PATH" -scheme "$SCHEME" -destination "$DESTINATION" -showdestinations 2>&1)" || {
  case "$DESTINATIONS_OUTPUT" in
    *license*)
      fail "Xcode license is not accepted. Run: sudo xcodebuild -license accept && sudo xcodebuild -runFirstLaunch"
      ;;
    *)
      if printf '%s\n' "$DESTINATIONS_OUTPUT" | grep -Eq 'iOS [0-9][^[:space:]]* is not installed|Please download and install the platform'; then
        fail "Xcode iOS platform is not fully installed for destination '$DESTINATION'. Run 'xcodebuild -downloadPlatform iOS' or open Xcode > Settings > Components, install iOS, then rerun preflight."
      fi
      fail "xcodebuild cannot resolve destinations for scheme '$SCHEME'. Output:
$DESTINATIONS_OUTPUT"
      ;;
  esac
}

if ! printf '%s\n' "$DESTINATIONS_OUTPUT" | awk -v needle="$DESTINATION_MATCH" '
  /Available destinations for|Destinations compatible with/ { section = "available"; next }
  /Ineligible destinations for|Destinations incompatible with/ { section = "ineligible"; next }
  section == "available" && index($0, needle) && $0 !~ /error:/ { found = 1 }
  END { exit found ? 0 : 1 }
'; then
  DESTINATION_ERROR="$(printf '%s\n' "$DESTINATIONS_OUTPUT" | awk -v needle="$DESTINATION_MATCH" '
    /Available destinations for|Destinations compatible with/ { section = "available"; next }
    /Ineligible destinations for|Destinations incompatible with/ { section = "ineligible"; next }
    section == "ineligible" && index($0, needle) { print; exit }
  ')"

  if [[ -n "$DESTINATION_ERROR" ]]; then
    fail "Xcode destination '$DESTINATION' is not eligible for scheme '$SCHEME': $DESTINATION_ERROR
Install the missing iOS platform first: run 'xcodebuild -downloadPlatform iOS' or open Xcode > Settings > Components, install iOS, then rerun preflight."
  fi

  if printf '%s\n' "$DESTINATIONS_OUTPUT" | grep -Eq 'iOS [0-9][^[:space:]]* is not installed|Please download and install the platform'; then
    fail "Xcode iOS platform is not fully installed for destination '$DESTINATION'. Run 'xcodebuild -downloadPlatform iOS' or open Xcode > Settings > Components, install iOS, then rerun preflight."
  fi

  fail "Xcode destination '$DESTINATION' is not available for scheme '$SCHEME'. Run 'xcodebuild -project \"$PROJECT_PATH\" -scheme \"$SCHEME\" -destination \"$DESTINATION\" -showdestinations' to inspect eligible destinations."
fi

info "iOS preflight OK"
info "project: $PROJECT_PATH"
info "scheme: $SCHEME"
info "bundle id: $BUNDLE_ID"
info "destination: $DESTINATION"
