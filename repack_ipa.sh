#!/bin/bash
# Repack the PvZ HD IPA with the fix dylib injected
# Run this on macOS after compiling PvZHDFix.dylib
#
# Usage: ./repack_ipa.sh /path/to/PvZ.ipa

set -e

IPA_PATH="$1"

if [ -z "$IPA_PATH" ]; then
    echo "Usage: $0 <path_to_ipa>"
    exit 1
fi

TEMP_DIR=$(mktemp -d)
echo "=== Extracting IPA ==="
unzip -q "$IPA_PATH" -d "$TEMP_DIR"

PAYLOAD="$TEMP_DIR/Payload"
APP_DIR=$(ls -d "$PAYLOAD"/*.app 2>/dev/null | head -1)

if [ -z "$APP_DIR" ]; then
    echo "ERROR: No .app found in Payload directory"
    exit 1
fi

BINARY_NAME=$(basename "$APP_DIR" .app)
BINARY_PATH="$APP_DIR/$BINARY_NAME"

echo "App: $APP_DIR"
echo "Binary: $BINARY_PATH"

# Copy the dylib
echo "=== Copying PvZHDFix.dylib ==="
if [ ! -f "PvZHDFix.dylib" ]; then
    echo "ERROR: PvZHDFix.dylib not found in current directory"
    echo "Build it first with ./build_dylib.sh"
    exit 1
fi

FRAMEWORKS_DIR="$APP_DIR/Frameworks"
mkdir -p "$FRAMEWORKS_DIR"
cp "PvZHDFix.dylib" "$FRAMEWORKS_DIR/"

# Remove old code signatures
echo "=== Removing old code signatures ==="
rm -rf "$APP_DIR/_CodeSignature" "$APP_DIR/CodeResources" 2>/dev/null || true

# Inject dylib load command
echo "=== Injecting dylib ==="
if command -v insert_dylib &>/dev/null; then
    insert_dylib --strip-codesig --inplace \
        "@rpath/PvZHDFix.dylib" \
        "$BINARY_PATH"
elif command -v optool &>/dev/null; then
    optool install -c load -p "@executable_path/Frameworks/PvZHDFix.dylib" -t "$BINARY_PATH"
else
    echo "ERROR: Need insert_dylib or optool"
    exit 1
fi

# Re-sign
echo "=== Re-signing ==="
if [ -f "Entitlements.plist" ]; then
    codesign -f -s "iPhone Developer" --entitlements Entitlements.plist "$APP_DIR"
else
    # Extract entitlements from the original binary
    codesign -d --entitlements :- "$BINARY_PATH" > Entitlements.plist 2>/dev/null || true
    codesign -f -s "iPhone Developer" --entitlements Entitlements.plist "$APP_DIR" 2>/dev/null || \
    codesign -f -s "iPhone Developer" "$APP_DIR"
fi

# Repack
echo "=== Repacking IPA ==="
OUTPUT="PvZ_HD_NoCrash.ipa"
cd "$TEMP_DIR"
zip -qr "$OUTPUT" Payload/
cd - > /dev/null
mv "$TEMP_DIR/$OUTPUT" .

echo ""
echo "=== Done! ==="
echo "Output: $OUTPUT"
echo ""
echo "Install with sideloading tool (AltStore, Sidestore, etc.)"
