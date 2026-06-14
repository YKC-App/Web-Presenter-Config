#!/usr/bin/env bash
#
# setup_ndi.sh — Mac-side setup for the NDI Monitor app.
#
# Copies the installed NDI SDK (static lib + headers) into Vendor/NDI/, ensures
# XcodeGen is installed, and generates the Xcode project. Run this on your Mac
# from the repository root:
#
#     ./scripts/setup_ndi.sh
#
# Override the SDK location if it is not the default:
#     NDI_SDK_DIR="/path/to/NDI SDK for Apple" ./scripts/setup_ndi.sh
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NDI_SDK_DIR="${NDI_SDK_DIR:-/Library/NDI SDK for Apple}"
VENDOR_DIR="$REPO_ROOT/Vendor/NDI"

echo "==> Repo:    $REPO_ROOT"
echo "==> SDK dir: $NDI_SDK_DIR"

# --- 1. Locate SDK pieces -----------------------------------------------------
HEADER="$NDI_SDK_DIR/include/Processing.NDI.Lib.h"
LIB="$NDI_SDK_DIR/lib/iOS/libndi_ios.a"

if [[ ! -f "$HEADER" ]]; then
  echo "ERROR: header not found: $HEADER" >&2
  echo "       Set NDI_SDK_DIR to your SDK install location and retry." >&2
  exit 1
fi
if [[ ! -f "$LIB" ]]; then
  echo "ERROR: static library not found: $LIB" >&2
  echo "       Expected libndi_ios.a — if you have an .xcframework instead," >&2
  echo "       update project.yml's dependency block accordingly." >&2
  exit 1
fi

# --- 2. Copy into Vendor/NDI (binaries are git-ignored) -----------------------
echo "==> Copying headers and library into Vendor/NDI/ ..."
mkdir -p "$VENDOR_DIR/include"
cp -R "$NDI_SDK_DIR/include/." "$VENDOR_DIR/include/"
cp "$LIB" "$VENDOR_DIR/libndi_ios.a"

if [[ ! -f "$VENDOR_DIR/module.modulemap" ]]; then
  echo "ERROR: $VENDOR_DIR/module.modulemap is missing (should be in git)." >&2
  exit 1
fi

# --- 3. Ensure XcodeGen --------------------------------------------------------
if ! command -v xcodegen >/dev/null 2>&1; then
  echo "==> XcodeGen not found; installing via Homebrew ..."
  brew install xcodegen
fi

# --- 4. Generate the project ---------------------------------------------------
echo "==> Generating Xcode project ..."
( cd "$REPO_ROOT" && xcodegen generate )

echo ""
echo "Done. Next:"
echo "  open \"$REPO_ROOT/NDIMonitor.xcodeproj\""
echo "  • Select your Team in Signing & Capabilities"
echo "  • Build & run on a physical iPad (NDI needs an arm64 device)"
