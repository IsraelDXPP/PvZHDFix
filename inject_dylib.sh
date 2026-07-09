#!/bin/bash
# Inject PvZHDFix.dylib into the PvZ HD binary
# Uses insert_dylib (from https://github.com/Tyilo/insert_dylib)
#
# Usage: ./inject_dylib.sh PvZHDFix.dylib /path/to/pvz

set -e

DYLIB_PATH="$1"
BINARY_PATH="$2"

if [ -z "$DYLIB_PATH" ] || [ -z "$BINARY_PATH" ]; then
    echo "Usage: $0 <dylib_path> <binary_path>"
    echo ""
    echo "Example:"
    echo "  $0 PvZHDFix.dylib Payload/pvz.app/pvz"
    exit 1
fi

if [ ! -f "$DYLIB_PATH" ]; then
    echo "ERROR: Dylib not found: $DYLIB_PATH"
    exit 1
fi

if [ ! -f "$BINARY_PATH" ]; then
    echo "ERROR: Binary not found: $BINARY_PATH"
    exit 1
fi

echo "=== Injecting dylib into binary ==="

# Copy the dylib to the app's Frameworks directory
FRAMEWORKS_DIR="$(dirname "$BINARY_PATH")/Frameworks"
mkdir -p "$FRAMEWORKS_DIR"
cp "$DYLIB_PATH" "$FRAMEWORKS_DIR/"

echo "Copied dylib to $FRAMEWORKS_DIR/"

# Check if insert_dylib is available
if command -v insert_dylib &>/dev/null; then
    insert_dylib --strip-codesig --inplace \
        "@rpath/PvZHDFix.dylib" \
        "$BINARY_PATH"
    echo "Dylib injected successfully!"
elif command -v optool &>/dev/null; then
    optool install \
        -c load \
        -p "@executable_path/Frameworks/PvZHDFix.dylib" \
        -t "$BINARY_PATH"
    echo "Dylib injected via optool!"
else
    echo "WARNING: Neither insert_dylib nor optool found."
    echo "Please install one of them:"
    echo "  brew install insert_dylib"
    echo "  or"
    echo "  brew install optool"
    echo ""
    echo "After injecting, re-sign and repack the IPA."
    exit 1
fi

echo ""
echo "=== Next steps ==="
echo "1. Re-sign the app with your developer certificate:"
echo "   codesign -f -s \"iPhone Developer\" --entitlements Entitlements.plist Payload/pvz.app"
echo ""
echo "2. Repack the IPA:"
echo "   zip -r PvZHD_Fixed.ipa Payload/"
echo ""
echo "3. Install with your preferred sideloading tool."
