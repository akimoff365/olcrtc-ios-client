#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${1:-}"
OUTPUT_DIR="$ROOT_DIR/build/ipa"
IPA_PATH="$OUTPUT_DIR/OlcRTCClient-unsigned.ipa"

if [[ -z "$APP_PATH" ]]; then
  APP_PATH="$(find "$ROOT_DIR/build/DerivedData/Build/Products/Release-iphoneos" -maxdepth 1 -name "OlcRTCClient.app" -type d | head -n 1)"
fi

if [[ -z "$APP_PATH" || ! -d "$APP_PATH" ]]; then
  echo "OlcRTCClient.app not found. Build the iphoneos Release app first." >&2
  exit 1
fi

rm -rf "$OUTPUT_DIR/Payload" "$IPA_PATH"
mkdir -p "$OUTPUT_DIR/Payload"
cp -R "$APP_PATH" "$OUTPUT_DIR/Payload/"

pushd "$OUTPUT_DIR" >/dev/null
zip -qry "$IPA_PATH" Payload
popd >/dev/null

echo "$IPA_PATH"
