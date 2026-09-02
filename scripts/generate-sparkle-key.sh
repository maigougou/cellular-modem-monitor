#!/bin/sh
set -eu

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 /secure/path/sparkle-ed25519-private-key" >&2
  exit 64
fi

output=$1
if [ -e "$output" ]; then
  echo "Refusing to overwrite existing key: $output" >&2
  exit 1
fi

output_dir=$(dirname -- "$output")
mkdir -p "$output_dir"
temporary_dir=$(mktemp -d /private/tmp/cellular-modem-monitor-sparkle-key.XXXXXX)
trap 'rm -rf "$temporary_dir"' EXIT HUP INT TERM
umask 077

private_der="$temporary_dir/private.der"
private_seed="$temporary_dir/private-seed.bin"
public_der="$temporary_dir/public.der"
public_key="$temporary_dir/public-key.bin"

openssl genpkey -algorithm Ed25519 -outform DER -out "$private_der"
private_size=$(stat -f '%z' "$private_der")
public_prefix_size=12
private_prefix_size=16
if [ "$private_size" -ne $((private_prefix_size + 32)) ]; then
  echo "OpenSSL produced an unexpected Ed25519 private key." >&2
  exit 1
fi
dd if="$private_der" of="$private_seed" bs=1 skip="$private_prefix_size" 2>/dev/null

openssl pkey -inform DER -in "$private_der" -pubout -outform DER -out "$public_der"
public_size=$(stat -f '%z' "$public_der")
if [ "$public_size" -ne $((public_prefix_size + 32)) ]; then
  echo "OpenSSL produced an unexpected Ed25519 public key." >&2
  exit 1
fi
dd if="$public_der" of="$public_key" bs=1 skip="$public_prefix_size" 2>/dev/null

base64 -i "$private_seed" -o "$output"
chmod 600 "$output"
public_base64=$(base64 -i "$public_key")

printf 'Private key: %s\n' "$output"
printf 'SUPublicEDKey: %s\n' "$public_base64"
