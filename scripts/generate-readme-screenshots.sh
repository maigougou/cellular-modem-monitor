#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
build_dir="$project_dir/.build/readme-screenshots"
module_cache="$project_dir/.build/module-cache"
generator="$build_dir/ReadmeScreenshotGenerator"

mkdir -p "$build_dir" "$module_cache"

set --
for source in "$project_dir"/Sources/SignalStatus/*.swift; do
  if [ "$(basename "$source")" != "SignalStatusApp.swift" ]; then
    set -- "$@" "$source"
  fi
done

sdk=${VOS5G_COMPATIBILITY_SDK:-/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk}
arch=$(uname -m)
swiftc \
  -parse-as-library \
  -sdk "$sdk" \
  -target "${arch}-apple-macosx13.0" \
  -module-cache-path "$module_cache" \
  "$project_dir/scripts/ReadmeScreenshotGenerator.swift" \
  "$@" \
  -o "$generator"

"$generator" "$project_dir/assets/cellular-modem-monitor-sa-n78.png" --demo-sa
"$generator" "$project_dir/assets/cellular-modem-monitor-nsa-n78-b2.png" --demo-controls

printf '%s\n' \
  "$project_dir/assets/cellular-modem-monitor-sa-n78.png" \
  "$project_dir/assets/cellular-modem-monitor-nsa-n78-b2.png"
