#!/bin/bash
# Build script for PvZHDFix standalone dylib
# Requires: Xcode with iOS SDK (macOS only)
#
# Usage: ./build_dylib.sh

set -e

echo "=== Building PvZHDFix.dylib ==="

# Check if we're on macOS with Xcode
if [ ! -d "$(xcode-select -p 2>/dev/null)" ]; then
    echo "ERROR: Xcode is required. Please install Xcode from the App Store."
    exit 1
fi

SDK_PATH=$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null)
if [ -z "$SDK_PATH" ]; then
    echo "ERROR: iOS SDK not found. Please install Xcode with iOS SDK."
    exit 1
fi

echo "Using SDK: $SDK_PATH"

# Compile fishhook and our hook code as a universal dylib
# arm64 for modern devices, armv7 for older devices
xcrun clang \
    -arch arm64 \
    -arch armv7 \
    -isysroot "$SDK_PATH" \
    -dynamiclib \
    -o PvZHDFix.dylib \
    PvZHDFix.m fishhook.c \
    -framework SystemConfiguration \
    -framework Foundation \
    -fobjc-arc \
    -O2 \
    -miphoneos-version-min=8.0 \
    -install_name @rpath/PvZHDFix.dylib

echo "=== Build complete! ==="
echo "Output: PvZHDFix.dylib"
echo ""
echo "To inject into the IPA:"
echo "  1. ./inject_dylib.sh PvZHDFix.dylib /path/to/Payload/pvz.app/pvz"
echo "  2. Copy PvZHDFix.dylib to Payload/pvz.app/Frameworks/"
echo "  3. Re-sign and repack the IPA"
