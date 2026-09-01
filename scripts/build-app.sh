#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
build_dir="$project_dir/.build/direct-release"
module_cache="$project_dir/.build/module-cache"
archive="$project_dir/dist/Cellular-Modem-Monitor-macOS.zip"
binary="$build_dir/CellularModemMonitor"

mkdir -p "$build_dir" "$module_cache" "$project_dir/dist"

sdk=${VOS5G_SDK:-$(xcrun --show-sdk-path)}
arch=$(uname -m)
signing_identity=${SIGNING_IDENTITY:--}

if [ "${REQUIRE_STABLE_SIGNING:-0}" = "1" ] && [ "$signing_identity" = "-" ]; then
  echo "REQUIRE_STABLE_SIGNING=1 requires SIGNING_IDENTITY to name a Developer ID Application certificate." >&2
  exit 1
fi

compile() {
  swiftc \
    -parse-as-library \
    -O \
    -sdk "$1" \
    -target "${arch}-apple-macosx13.0" \
    -module-cache-path "$module_cache" \
    "$project_dir"/Sources/SignalStatus/*.swift \
    -o "$binary"
}

compiled=0
if compile "$sdk" 2>"$build_dir/compiler.log"; then
  compiled=1
else
  # Some Command Line Tools-only installations expose a macro-based SwiftUI
  # SDK without shipping its matching host plugin. Try bundled compatibility
  # SDKs that still support the macOS 13 deployment target before failing.
  compatibility_sdk=${VOS5G_COMPATIBILITY_SDK:-/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk}
  legacy_sdk=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
  for candidate in "$compatibility_sdk" "$legacy_sdk"; do
    if [ "$candidate" != "$sdk" ] && [ -d "$candidate" ] && \
       compile "$candidate" 2>"$build_dir/compiler.log"; then
      sdk=$candidate
      compiled=1
      break
    fi
  done
fi
if [ "$compiled" -ne 1 ]; then
  cat "$build_dir/compiler.log" >&2
  exit 1
fi

staging_dir=$(mktemp -d /private/tmp/cellular-modem-monitor-build.XXXXXX)
trap 'rm -rf "$staging_dir"' EXIT HUP INT TERM
staging_app="$staging_dir/Cellular Modem Monitor.app"
staging_archive="$staging_dir/Cellular-Modem-Monitor-macOS.zip"

mkdir -p "$staging_app/Contents/MacOS" "$staging_app/Contents/Resources"
cp "$binary" "$staging_app/Contents/MacOS/CellularModemMonitor"
cp "$project_dir/Resources/Info.plist" "$staging_app/Contents/Info.plist"
cp "$project_dir/Resources/ModemSignalSSHAskPass.sh" "$staging_app/Contents/Resources/ModemSignalSSHAskPass.sh"
icon_path=$(SIGNAL_STATUS_ICON_WORK_DIR="$staging_dir/icon" "$project_dir/scripts/generate-icon.sh")
cp "$icon_path" "$staging_app/Contents/Resources/AppIcon.icns"
chmod 755 "$staging_app/Contents/MacOS/CellularModemMonitor" "$staging_app/Contents/Resources/ModemSignalSSHAskPass.sh"
chmod 644 "$staging_app/Contents/Info.plist" "$staging_app/Contents/Resources/AppIcon.icns"
xattr -cr "$staging_app"
if [ "$signing_identity" = "-" ]; then
  # Useful for local/source builds. A public release should still provide a
  # stable Developer ID identity for normal Gatekeeper upgrade continuity.
  codesign --force --sign - --timestamp=none "$staging_app" >/dev/null
else
  codesign --force --options runtime --timestamp --sign "$signing_identity" "$staging_app" >/dev/null
fi
codesign --verify --deep --strict "$staging_app"
(cd "$staging_dir" && COPYFILE_DISABLE=1 /usr/bin/zip -qry -X "$staging_archive" "Cellular Modem Monitor.app")

# Keep the signed application inside the ZIP. Copying an expanded .app onto
# some external volumes can create a hidden resource fork on the .icns file.
# A single ZIP file crosses those volumes unchanged and expands cleanly on the
# user's Mac.
cp "$staging_archive" "$archive"
cmp -s "$staging_archive" "$archive"
unzip -tq "$archive" >/dev/null

printf 'Archive: %s\n' "$archive"
printf 'SDK: %s\n' "$sdk"
printf 'Signing identity: %s\n' "$signing_identity"
if [ "$signing_identity" = "-" ]; then
  printf '%s\n' 'Warning: this is an ad-hoc local build; use a stable Developer ID identity for public upgrade continuity.' >&2
fi
