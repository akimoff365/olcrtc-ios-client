#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR_DIR="$ROOT_DIR/Vendor"
FRAMEWORK_DIR="$ROOT_DIR/Frameworks"
OLCRTC_DIR="$VENDOR_DIR/olcrtc"

mkdir -p "$VENDOR_DIR" "$FRAMEWORK_DIR"

if [[ ! -d "$OLCRTC_DIR/.git" ]]; then
  git clone https://github.com/openlibrecommunity/olcrtc "$OLCRTC_DIR" --recurse-submodules
else
  git -C "$OLCRTC_DIR" pull --ff-only
fi

pushd "$OLCRTC_DIR" >/dev/null
gomobile bind -target=ios -o "$FRAMEWORK_DIR/Mobile.xcframework" ./mobile
popd >/dev/null

echo "Built $FRAMEWORK_DIR/Mobile.xcframework"
