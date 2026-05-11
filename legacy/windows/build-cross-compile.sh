#!/bin/bash
# Cross-compile monitor_switcher.exe on macOS for Windows

set -e

echo "Cross-compiling monitor_switcher.exe for Windows..."
echo ""

# Check if mingw-w64 is installed
if ! command -v x86_64-w64-mingw32-g++ &> /dev/null; then
    echo "Error: mingw-w64 not found"
    echo "Install it with: brew install mingw-w64"
    exit 1
fi

# Navigate to windows directory
cd "$(dirname "$0")"

# Create bin directory if it doesn't exist
mkdir -p ../bin

# Cross-compile directly to bin directory
echo "Compiling..."
x86_64-w64-mingw32-g++ \
    -std=c++17 \
    -O2 \
    -static \
    -static-libgcc \
    -static-libstdc++ \
    -o ../bin/monitor_switcher.exe \
    monitor_switcher.cpp \
    -ldxva2 \
    -lgdi32 \
    -luser32

echo ""
echo "Build complete!"
echo "Output: bin/monitor_switcher.exe"
echo ""
echo "Note: This .exe can only run on Windows, not macOS"
echo "Transfer it to your Windows machine to test."
