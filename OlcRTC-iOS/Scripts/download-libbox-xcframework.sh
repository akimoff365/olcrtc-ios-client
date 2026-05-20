#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FRAMEWORK_DIR="$ROOT_DIR/Frameworks"
VERSION="v1.13.11"
URL="https://github.com/proother/sing-box-lib/releases/download/${VERSION}/Libbox-ios.xcframework.zip"
SHA256="d4feaa8cdf87ca4100dcf26a2d447772878a8129750f8b991743e43cae6bde71"
ARCHIVE="$FRAMEWORK_DIR/Libbox-ios.xcframework.zip"

mkdir -p "$FRAMEWORK_DIR"

if [[ -d "$FRAMEWORK_DIR/Libbox.xcframework" ]]; then
  echo "Libbox.xcframework already exists"
  exit 0
fi

curl -L --fail --retry 3 --retry-delay 2 "$URL" -o "$ARCHIVE"

ACTUAL_SHA="$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')"
if [[ "$ACTUAL_SHA" != "$SHA256" ]]; then
  echo "Libbox checksum mismatch: expected $SHA256, got $ACTUAL_SHA" >&2
  exit 1
fi

unzip -q "$ARCHIVE" -d "$FRAMEWORK_DIR"
rm -f "$ARCHIVE"

for plist in "$FRAMEWORK_DIR"/Libbox.xcframework/*/Libbox.framework/Versions/A/Resources/Info.plist; do
  /usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string Libbox" "$plist" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Set :CFBundleExecutable Libbox" "$plist"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string io.nekohasekai.libbox" "$plist" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier io.nekohasekai.libbox" "$plist"
  /usr/libexec/PlistBuddy -c "Add :CFBundleInfoDictionaryVersion string 6.0" "$plist" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Set :CFBundleInfoDictionaryVersion 6.0" "$plist"
  /usr/libexec/PlistBuddy -c "Add :CFBundleName string Libbox" "$plist" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Set :CFBundleName Libbox" "$plist"
  /usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string FMWK" "$plist" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Set :CFBundlePackageType FMWK" "$plist"
  /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string ${VERSION#v}" "$plist" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION#v}" "$plist"
  /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string ${VERSION#v}" "$plist" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${VERSION#v}" "$plist"
done

echo "Downloaded Libbox.xcframework ${VERSION}"
