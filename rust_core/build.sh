#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════
#  IntelliState Rust Core — Build Script
# ═══════════════════════════════════════════════════════════════════════
#
# Builds the Rust core library as a dynamic library (.dylib/.so/.dll)
# for use with Dart FFI.
#
# Usage:
#   ./build.sh          # Debug build
#   ./build.sh release  # Release build (optimized)
#
# Output:
#   target/debug/libintellistate_core.dylib    (macOS debug)
#   target/release/libintellistate_core.dylib  (macOS release)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

MODE="${1:-debug}"

echo "═══════════════════════════════════════════════"
echo "  IntelliState Rust Core — Building ($MODE)"
echo "═══════════════════════════════════════════════"

if [ "$MODE" = "release" ]; then
    cargo build --release
    LIB_PATH="target/release"
else
    cargo build
    LIB_PATH="target/debug"
fi

# Detect platform and library extension
case "$(uname -s)" in
    Darwin)
        LIB_EXT="dylib"
        ;;
    Linux)
        LIB_EXT="so"
        ;;
    MINGW*|MSYS*|CYGWIN*)
        LIB_EXT="dll"
        ;;
    *)
        echo "Unknown platform: $(uname -s)"
        exit 1
        ;;
esac

LIB_FILE="$LIB_PATH/libintellistate_core.$LIB_EXT"

if [ -f "$LIB_FILE" ]; then
    echo ""
    echo "✅ Build successful!"
    echo "   Library: $LIB_FILE"
    echo "   Size: $(du -h "$LIB_FILE" | cut -f1)"
    echo ""
    
    # Copy to a well-known location for Dart FFI to find
    DART_LIB_DIR="$SCRIPT_DIR/../native"
    mkdir -p "$DART_LIB_DIR"
    cp "$LIB_FILE" "$DART_LIB_DIR/"
    echo "   Copied to: $DART_LIB_DIR/libintellistate_core.$LIB_EXT"
else
    echo "❌ Build failed — library not found at $LIB_FILE"
    exit 1
fi
