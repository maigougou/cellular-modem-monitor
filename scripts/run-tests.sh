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
    "$project_dir/Sources/SignalStatus/Localization.swift" \
    "$project_dir/Sources/SignalStatus/Models.swift" \
    "$project_dir/Sources/SignalStatus/QMIParser.swift" \
    "$project_dir/Sources/SignalStatus/VOSClient.swift" \
    "$project_dir/Sources/SignalStatus/CredentialStore.swift" \
    "$project_dir/Sources/SignalStatus/ModemBackend.swift" \
    "$project_dir/Sources/SignalStatus/ModemControlBackend.swift" \
    "$project_dir/Sources/SignalStatus/VOSBackend.swift" \
    "$project_dir/Sources/SignalStatus/VOSControlSession.swift" \
    "$project_dir/Sources/SignalStatus/NetworkTopology.swift" \
    "$project_dir/Sources/SignalStatus/ModemDiscovery.swift" \
    "$project_dir/Sources/SignalStatus/ZTEUBusTransport.swift" \
    "$project_dir/Sources/SignalStatus/ZTEAuthSession.swift" \
    "$project_dir/Sources/SignalStatus/MC7530Parser.swift" \
    "$project_dir/Sources/SignalStatus/MC7530ControlSession.swift" \
    "$project_dir/Sources/SignalStatus/MC7530Backend.swift" \
    "$project_dir/Sources/SignalStatus/ModemCoordinator.swift" \
    "$project_dir/Sources/SignalStatus/StatusModel.swift" \
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

SIGNAL_STATUS_TEST_FIXTURES="$project_dir/Tests/SignalStatusTests/Fixtures" \
  "$build_dir/SignalStatusTests"

# Build and link the complete application surface under Swift 6 strict
# concurrency. The executable tests above intentionally omit the app's @main
# entry point, while this gate includes the SwiftUI panel and entry files so
# release-only compiler or linker failures cannot hide outside the direct test
# target.
#
# Some Command Line Tools-only installations ship the macro-based SwiftUI
# interface from macOS 26/27 without the matching SwiftUIMacros host plugin.
# In that incomplete toolchain configuration, use the newest pre-macro SDK that
# is bundled alongside it. The deployment target remains macOS 13.0.
full_source_sdk=${VOS5G_FULL_SOURCE_SDK:-$sdk}
if [ -z "${VOS5G_FULL_SOURCE_SDK:-}" ]; then
  swiftc_path=$(xcrun --find swiftc)
  host_plugins=$(CDPATH= cd -- "$(dirname -- "$swiftc_path")/../lib/swift/host/plugins" 2>/dev/null && pwd || true)
  swiftui_macro_plugin=
  if [ -n "$host_plugins" ]; then
    swiftui_macro_plugin=$(find "$host_plugins" -iname '*swiftuimacros*' -print -quit 2>/dev/null || true)
  fi

  compatibility_sdk=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk
  if [ -z "$swiftui_macro_plugin" ] && [ -d "$compatibility_sdk" ]; then
    full_source_sdk=$compatibility_sdk
  fi
fi

full_source_binary="$build_dir/CellularModemMonitorCompileCheck"
full_source_log="$build_dir/full-source-compiler.log"
if ! swiftc \
  -swift-version 6 \
  -strict-concurrency=complete \
  -parse-as-library \
  -sdk "$full_source_sdk" \
  -target "${arch}-apple-macosx13.0" \
  -module-cache-path "$module_cache" \
  "$project_dir"/Sources/SignalStatus/*.swift \
  -o "$full_source_binary" \
  2>"$full_source_log"; then
  cat "$full_source_log" >&2
  exit 1
fi

printf 'Full-source compile SDK: %s\n' "$full_source_sdk"
