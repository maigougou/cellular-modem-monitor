#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
variant=${1:-current}
case "$variant" in current|baseline) ;; *) echo 'Use current or baseline' >&2; exit 2 ;; esac
source_dir=$(mktemp -d /private/tmp/cmm-efficiency-benchmark.XXXXXX)
trap 'rm -rf "$source_dir"' EXIT HUP INT TERM
build_dir="$project_dir/.build/efficiency-benchmark"
mkdir -p "$build_dir" "$project_dir/.build/module-cache"
if [ "$variant" = baseline ]; then
    # Pin the comparison to the already released version, not a moving branch.
    baseline=6f4f8430d133e124579680817c643584838fdd07
    git -C "$project_dir" cat-file -e "$baseline^{commit}"
    git -C "$project_dir" archive "$baseline" Sources | tar -x -C "$source_dir"
else
    cp -R "$project_dir/Sources" "$source_dir/"
fi
# Mechanical test-only access relaxation in disposable sources. This never
# changes repository files or the installed application.
perl -pi -e 's/private\(set\) var /var /g; s/private func (persistLastSuccessful|updateMenuTitle)/func $1/g' \
    "$source_dir/Sources/SignalStatus/StatusModel.swift"
cp "$project_dir/scripts/EfficiencyBenchmark.swift" "$source_dir/Sources/SignalStatus/SignalStatusApp.swift"
if [ "$variant" = baseline ]; then set -- -D BASELINE_PERFORMANCE; else set --; fi
swiftc -parse-as-library -O \
    -sdk /Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk \
    -target "$(uname -m)-apple-macosx13.0" \
    -module-cache-path "$project_dir/.build/module-cache" \
    "$@" "$source_dir"/Sources/SignalStatus/*.swift \
    -o "$build_dir/$variant"
printf 'Built %s\n' "$build_dir/$variant"
