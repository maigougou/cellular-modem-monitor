#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
info_plist="$project_dir/Resources/Info.plist"
archive="$project_dir/dist/Cellular-Modem-Monitor-macOS.zip"
appcast="$project_dir/appcast.xml"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info_plist")
build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info_plist")
tag=${1:-v$version}
private_key=${SPARKLE_EDDSA_KEY_FILE:-}

if [ -z "$private_key" ] || [ ! -f "$private_key" ]; then
  echo "Set SPARKLE_EDDSA_KEY_FILE to the protected Ed25519 key file." >&2
  exit 64
fi
if [ ! -f "$archive" ]; then
  echo "Missing release archive. Run make build first: $archive" >&2
  exit 1
fi

sparkle_dir=${SPARKLE_DIST_DIR:-$("$project_dir/scripts/ensure-sparkle.sh")}
generate_appcast="$sparkle_dir/bin/generate_appcast"
sign_update="$sparkle_dir/bin/sign_update"
work_dir=$(mktemp -d /private/tmp/cellular-modem-monitor-appcast.XXXXXX)
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM

cp "$archive" "$work_dir/Cellular-Modem-Monitor-macOS.zip"
if [ -f "$appcast" ]; then
  cp "$appcast" "$work_dir/appcast.xml"
fi

"$generate_appcast" \
  --ed-key-file "$private_key" \
  --download-url-prefix "https://github.com/maigougou/cellular-modem-monitor/releases/download/$tag/" \
  --link "https://github.com/maigougou/cellular-modem-monitor" \
  --maximum-versions 5 \
  --maximum-deltas 0 \
  -o "$work_dir/appcast.xml" \
  "$work_dir"

"$sign_update" --ed-key-file "$private_key" --verify "$work_dir/appcast.xml"
cp "$work_dir/appcast.xml" "$appcast"
chmod 644 "$appcast"

printf 'Version: %s (%s)\n' "$version" "$build"
printf 'Tag: %s\n' "$tag"
printf 'Appcast: %s\n' "$appcast"
printf 'Archive: %s\n' "$archive"
