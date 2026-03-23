#!/usr/bin/env bash
# setup_whisper.sh — Build whisper-cli and download the small.en model.
# Supports Linux, macOS, and Windows (MSYS/Git Bash).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BIN_DIR="$PROJECT_DIR/bin"
MODEL_DIR="$PROJECT_DIR/models"
TMP_DIR=$(mktemp -d)

cleanup() {
    echo "Cleaning up temp directory..."
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

# Detect OS
case "$(uname -s)" in
    Linux*)   OS="linux";;
    Darwin*)  OS="macos";;
    MINGW*|MSYS*|CYGWIN*) OS="windows";;
    *)        echo "Unsupported OS: $(uname -s)"; exit 1;;
esac

echo "=== whisper.cpp setup ==="
echo "OS:          $OS"
echo "Project dir: $PROJECT_DIR"
echo ""

# Check dependencies
for cmd in git cmake make; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "ERROR: '$cmd' is required but not found. Please install it."
        exit 1
    fi
done

# Clone whisper.cpp
echo "Cloning whisper.cpp..."
git clone --depth 1 https://github.com/ggml-org/whisper.cpp.git "$TMP_DIR/whisper.cpp"

# Build
echo "Building whisper-cli..."
cd "$TMP_DIR/whisper.cpp"
mkdir -p build && cd build

CMAKE_ARGS="-DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF"

# Detect CUDA
if command -v nvcc &>/dev/null; then
    echo "CUDA detected — enabling GPU support"
    CMAKE_ARGS="$CMAKE_ARGS -DGGML_CUDA=ON"
else
    echo "No CUDA detected — building CPU-only"
fi

cmake .. $CMAKE_ARGS
cmake --build . --config Release -j "$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)"

# Find and copy binary
mkdir -p "$BIN_DIR"

if [ "$OS" = "windows" ]; then
    BINARY_NAME="whisper-cli.exe"
else
    BINARY_NAME="whisper-cli"
fi

# whisper.cpp build output location varies; search for it
BUILT_BIN=$(find "$TMP_DIR/whisper.cpp/build" -name "$BINARY_NAME" -type f | head -1)

if [ -z "$BUILT_BIN" ]; then
    echo "ERROR: Could not find built $BINARY_NAME"
    exit 1
fi

cp "$BUILT_BIN" "$BIN_DIR/$BINARY_NAME"
chmod +x "$BIN_DIR/$BINARY_NAME"
echo "Installed: $BIN_DIR/$BINARY_NAME"

# Download model
echo ""
echo "Downloading ggml-small.en model..."
mkdir -p "$MODEL_DIR"

cd "$TMP_DIR/whisper.cpp"
bash models/download-ggml-model.sh small.en

cp models/ggml-small.en.bin "$MODEL_DIR/ggml-small.en.bin"
echo "Installed: $MODEL_DIR/ggml-small.en.bin"

echo ""
echo "=== Setup complete ==="
echo "Binary: $BIN_DIR/$BINARY_NAME"
echo "Model:  $MODEL_DIR/ggml-small.en.bin"
