#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
build_dir="$project_dir/.build/quick-menu-ui-tests"
mkdir -p "$build_dir" "$project_dir/.build/module-cache"
source_dir=$(mktemp -d /private/tmp/cmm-quick-menu-ui.XXXXXX)
trap 'rm -rf "$source_dir"' EXIT HUP INT TERM
for source in "$project_dir"/Sources/SignalStatus/*.swift; do
  if [ "$(basename "$source")" != "SignalStatusApp.swift" ]; then
    cp "$source" "$source_dir/"
  fi
done
cp "$project_dir/scripts/QuickArchitectureMenuUITests.swift" "$source_dir/"
sdk=${VOS5G_COMPATIBILITY_SDK:-/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk}
swiftc -parse-as-library -sdk "$sdk" -target "$(uname -m)-apple-macosx13.0" \
  -module-cache-path "$project_dir/.build/module-cache" \
  "$source_dir"/*.swift -o "$build_dir/QuickArchitectureMenuUITests"
if [ "${1:-}" != "--compile-only" ]; then
  "$build_dir/QuickArchitectureMenuUITests"
fi
