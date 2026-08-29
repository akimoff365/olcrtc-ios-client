#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR_DIR="$ROOT_DIR/Vendor"
FRAMEWORK_DIR="$ROOT_DIR/Frameworks"
OLCRTC_DIR="$VENDOR_DIR/olcrtc"
# Pin to the last upstream commit before the global mobile refactor.
# Later commits moved the client API to Runtime-based configuration and break the iOS bindings.
OLCRTC_REF="${OLCRTC_REF:-3339cd36716885e583429f97e73462cde4984e2e}"

mkdir -p "$VENDOR_DIR" "$FRAMEWORK_DIR"

if [[ ! -d "$OLCRTC_DIR/.git" ]]; then
  git clone https://github.com/openlibrecommunity/olcrtc "$OLCRTC_DIR" --recurse-submodules
fi

if git -C "$OLCRTC_DIR" ls-remote --exit-code --heads origin "$OLCRTC_REF" >/dev/null 2>&1; then
  git -C "$OLCRTC_DIR" fetch origin "$OLCRTC_REF"
  git -C "$OLCRTC_DIR" checkout "$OLCRTC_REF"
  git -C "$OLCRTC_DIR" pull --ff-only origin "$OLCRTC_REF"
  git -C "$OLCRTC_DIR" reset --hard "origin/$OLCRTC_REF"
else
  git -C "$OLCRTC_DIR" fetch --all --tags --prune
  git -C "$OLCRTC_DIR" checkout "$OLCRTC_REF"
  git -C "$OLCRTC_DIR" reset --hard "$OLCRTC_REF"
fi

git -C "$OLCRTC_DIR" submodule update --init --recursive

pushd "$OLCRTC_DIR" >/dev/null
echo "Using olcRTC $(git rev-parse --short HEAD) from $OLCRTC_REF"
for patch_file in "$ROOT_DIR"/Patches/*.patch; do
  [[ -e "$patch_file" ]] || continue
  if git apply --check "$patch_file" >/dev/null 2>&1; then
    echo "Applying $(basename "$patch_file")"
    git apply "$patch_file"
  else
    echo "Skipping $(basename "$patch_file") (not applicable to current upstream ref)"
  fi
done

if grep -Eq 'type Runtime struct|func New\(\) \*Runtime' "$OLCRTC_DIR"/mobile/*.go 2>/dev/null; then
  cat > "$OLCRTC_DIR/mobile/compat.go" <<'EOF'
package mobile

import "fmt"

var compatRuntime = New()

func MobileSetProviders() {}

func MobileSetDNS(dnsServer string) {
  _ = compatRuntime.SetDNS(dnsServer)
}

func MobileSetTransport(transport string) {
  _ = compatRuntime.SetTransport(transport)
}

func MobileSetLivenessOptions(intervalMillis, timeoutMillis, failures int) {
  _ = compatRuntime.SetLivenessOptions(intervalMillis, timeoutMillis, failures)
}

func MobileSetVP8Options(fps, batchSize int) {
  _ = compatRuntime.SetVP8Options(fps, batchSize)
}

func MobileSetSEIOptions(fps, batchSize, fragmentSize, ackTimeoutMS int) {
  _ = compatRuntime.SetSEIOptions(fps, batchSize, fragmentSize, ackTimeoutMS)
}

func MobileSetVideoOptions(
  width, height, fps int,
  bitrate, hw string,
  qrSize int,
  qrRecovery, codec string,
  tileModule, tileRS int,
) {
  _ = compatRuntime.SetVideoOptions(width, height, fps, qrSize, qrRecovery, codec, tileModule, tileRS)
}

func MobileStartWithTransport(
  carrier, transport, roomID, clientID, keyHex string,
  socksPort int,
  socksUser, socksPass string,
  errPtr *error,
) bool {
  if errPtr != nil {
    *errPtr = nil
  }
  provider := "none"
  switch carrier {
  case "jitsi", "telemost", "wbstream", "none":
    provider = carrier
  default:
    provider = "jitsi"
  }
  if e := compatRuntime.SetProvider(provider); e != nil {
    setCompatError(errPtr, e)
    return false
  }
  if e := compatRuntime.SetTransport(transport); e != nil {
    setCompatError(errPtr, e)
    return false
  }
  if roomID != "" {
    compatRuntime.SetRoom(roomID)
  }
  if clientID != "" {
    compatRuntime.SetDeviceID(clientID)
  }
  if keyHex != "" {
    if e := compatRuntime.SetKey(keyHex); e != nil {
      setCompatError(errPtr, e)
      return false
    }
  }
  if socksPort > 0 {
    if e := compatRuntime.SetSocksPort(socksPort); e != nil {
      setCompatError(errPtr, e)
      return false
    }
  }
  if e := compatRuntime.SetSocksCredentials(socksUser, socksPass); e != nil {
    setCompatError(errPtr, e)
    return false
  }
  if e := compatRuntime.SetDNS("8.8.8.8:53"); e != nil {
    setCompatError(errPtr, e)
    return false
  }
  if e := compatRuntime.Start(); e != nil {
    setCompatError(errPtr, e)
    return false
  }
  return true
}

func MobileWaitReady(timeoutMillis int, errPtr *error) bool {
  if errPtr != nil {
    *errPtr = nil
  }
  if err := compatRuntime.WaitReady(timeoutMillis); err != nil {
    setCompatError(errPtr, err)
    return false
  }
  return true
}

func MobileStop() {
  _ = compatRuntime.Stop(5000)
}

func setCompatError(errPtr *error, err error) {
  if errPtr != nil {
    *errPtr = fmt.Errorf("mobile compat: %w", err)
  }
}
EOF
fi

gomobile bind -target=ios -o "$FRAMEWORK_DIR/Mobile.xcframework" ./mobile
popd >/dev/null

echo "Built $FRAMEWORK_DIR/Mobile.xcframework"
