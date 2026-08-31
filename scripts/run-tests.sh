#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
build_dir="$project_dir/.build/direct-tests"
module_cache="$project_dir/.build/module-cache"
mkdir -p "$build_dir" "$module_cache"

sdk=${VOS5G_SDK:-$(xcrun --show-sdk-path)}
arch=$(uname -m)

compile() {
  swiftc \
    -parse-as-library \
    -sdk "$1" \
    -target "${arch}-apple-macosx13.0" \
    -module-cache-path "$module_cache" \
    "$project_dir/Sources/SignalStatus/Models.swift" \
    "$project_dir/Sources/SignalStatus/QMIParser.swift" \
    "$project_dir/Sources/SignalStatus/VOSClient.swift" \
    "$project_dir/scripts/DirectTests.swift" \
    -o "$build_dir/SignalStatusTests"
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

"$build_dir/SignalStatusTests"
