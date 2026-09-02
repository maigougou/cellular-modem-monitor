#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
version=2.9.6
expected_sha256=52bf9e88cdd972fc0c81501377a880e90d47031bd8ca5462488f843e2609e192
vendor_dir="$project_dir/.build/vendor"
distribution_dir="$vendor_dir/Sparkle-$version"
archive="$vendor_dir/Sparkle-$version.tar.xz"
framework="$distribution_dir/Sparkle.framework/Versions/B/Sparkle"

if [ ! -f "$framework" ]; then
  mkdir -p "$vendor_dir"
  if [ ! -f "$archive" ]; then
    temporary_archive="$archive.download"
    curl \
      --fail \
      --location \
      --retry 3 \
      --proto '=https' \
      --tlsv1.2 \
      --output "$temporary_archive" \
      "https://github.com/sparkle-project/Sparkle/releases/download/$version/Sparkle-$version.tar.xz"
    mv "$temporary_archive" "$archive"
  fi

  actual_sha256=$(shasum -a 256 "$archive" | awk '{print $1}')
  if [ "$actual_sha256" != "$expected_sha256" ]; then
    echo "Sparkle archive checksum mismatch: $actual_sha256" >&2
    exit 1
  fi

  if [ -e "$distribution_dir" ]; then
    echo "Incomplete Sparkle directory already exists: $distribution_dir" >&2
    echo "Run 'make clean' and retry." >&2
    exit 1
  fi

  extraction_dir=$(mktemp -d "$vendor_dir/Sparkle-$version.extract.XXXXXX")
  trap 'rm -rf "$extraction_dir"' EXIT HUP INT TERM
  tar -xJf "$archive" -C "$extraction_dir"
  mv "$extraction_dir" "$distribution_dir"
  trap - EXIT HUP INT TERM
fi

printf '%s\n' "$distribution_dir"
