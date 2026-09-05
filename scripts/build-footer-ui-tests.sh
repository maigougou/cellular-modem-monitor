#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
build_dir="$project_dir/.build/footer-ui-tests"
mkdir -p "$build_dir" "$project_dir/.build/module-cache"
source_dir=$(mktemp -d /private/tmp/cmm-footer-ui.XXXXXX)
trap 'rm -rf "$source_dir"' EXIT HUP INT TERM
cp -R "$project_dir/Sources" "$source_dir/"
cp "$project_dir/scripts/FooterUITests.swift" "$source_dir/Sources/SignalStatus/SignalStatusApp.swift"
swiftc -parse-as-library -sdk /Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk \
  -target "$(uname -m)-apple-macosx13.0" -module-cache-path "$project_dir/.build/module-cache" \
  "$source_dir"/Sources/SignalStatus/*.swift -o "$build_dir/FooterUITests"
printf 'Built %s\n' "$build_dir/FooterUITests"
