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

if ! compile "$sdk" 2>"$build_dir/compiler.log"; then
  fallback=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
  if [ "$sdk" != "$fallback" ] && [ -d "$fallback" ]; then
    sdk=$fallback
    compile "$sdk"
  else
    cat "$build_dir/compiler.log" >&2
    exit 1
  fi
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
codesign --force --sign - --timestamp=none "$staging_app" >/dev/null
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
