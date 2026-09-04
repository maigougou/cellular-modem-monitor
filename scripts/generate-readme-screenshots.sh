#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
build_dir="$project_dir/.build/readme-screenshots"
module_cache="$project_dir/.build/module-cache"
generator="$build_dir/ReadmeScreenshotGenerator"
output_dir="$project_dir/assets/previews"

mkdir -p "$build_dir" "$module_cache"

if [ "${1:-}" != "--render-only" ]; then
  # Compile a stable local snapshot when the checkout lives on a mounted volume.
  source_dir=$(mktemp -d /private/tmp/cmm-readme-sources.XXXXXX)
  trap 'rm -rf "$source_dir"' EXIT HUP INT TERM
  for source in "$project_dir"/Sources/SignalStatus/*.swift; do
    if [ "$(basename "$source")" != "SignalStatusApp.swift" ]; then
      cp "$source" "$source_dir/"
    fi
  done
  cp "$project_dir/scripts/ReadmeScreenshotGenerator.swift" "$source_dir/"
  sdk=${VOS5G_COMPATIBILITY_SDK:-/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk}
  arch=$(uname -m)
  swiftc \
    -parse-as-library -D README_SCREENSHOTS \
    -sdk "$sdk" \
    -target "${arch}-apple-macosx13.0" \
    -module-cache-path "$module_cache" \
    -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker "$project_dir/Resources/Info.plist" \
    "$source_dir"/*.swift \
    -o "$generator"
fi

if [ "${1:-}" = "--compile-only" ]; then exit 0; fi

scenes=${README_SCENES:-"overview sa nsa ca connection radio nr-ca lte-ca controls speedtest details settings"}
for language in en zh-CN; do
  mkdir -p "$output_dir/$language"
  for scene in $scenes; do
    for theme in light dark; do
      if [ "$language" = "zh-CN" ]; then
        "$generator" "$output_dir/$language/$scene-$theme.png" --scene "$scene" "--$theme" --chinese
      else
        "$generator" "$output_dir/$language/$scene-$theme.png" --scene "$scene" "--$theme"
      fi
    done
  done
done
