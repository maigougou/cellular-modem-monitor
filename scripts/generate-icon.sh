#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
work_dir=${SIGNAL_STATUS_ICON_WORK_DIR:-"$project_dir/.build/icon"}
module_cache="$project_dir/.build/module-cache"

rm -rf "$work_dir"
mkdir -p "$work_dir" "$module_cache"

sdk=${VOS5G_SDK:-$(xcrun --show-sdk-path)}
arch=$(uname -m)
generator="$work_dir/IconGenerator"
source_png="$work_dir/AppIcon.png"
output_icns="$work_dir/AppIcon.icns"

compile_generator() {
  swiftc \
    -parse-as-library \
    -sdk "$1" \
    -target "${arch}-apple-macosx13.0" \
    -module-cache-path "$module_cache" \
    "$project_dir/scripts/IconGenerator.swift" \
    -o "$generator"
}

if ! compile_generator "$sdk" 2>"$work_dir/compiler.log"; then
  fallback=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
  if [ "$sdk" != "$fallback" ] && [ -d "$fallback" ]; then
    sdk=$fallback
    compile_generator "$sdk"
  else
    cat "$work_dir/compiler.log" >&2
    exit 1
  fi
fi

"$generator" "$source_png" "$output_icns"
printf '%s\n' "$output_icns"
