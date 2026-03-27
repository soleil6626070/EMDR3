#!/usr/bin/env bash
# setup_luasec.sh — Build luasec and vendor into lib/ for Love2D.
# Produces: lib/ssl.so, lib/ssl.lua, lib/ssl/https.lua
# Requires: git, gcc/make, libssl-dev, lua5.1 headers (or LuaJIT)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB_DIR="$PROJECT_DIR/lib"
TMP_DIR=$(mktemp -d)

LUASEC_VERSION="v1.3.2"

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

echo "=== luasec setup ==="
echo "OS:          $OS"
echo "Project dir: $PROJECT_DIR"
echo ""

# Check dependencies
for cmd in git gcc make; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "ERROR: '$cmd' is required but not found. Please install it."
        exit 1
    fi
done

# Check for OpenSSL headers
if [ "$OS" = "linux" ]; then
    if ! dpkg -s libssl-dev &>/dev/null 2>&1; then
        echo "ERROR: libssl-dev is required. Install with: sudo apt install libssl-dev"
        exit 1
    fi
fi

# Find Lua/LuaJIT headers
LUA_INC=""
for dir in /usr/include/luajit-2.1 /usr/include/lua5.1 /usr/local/include/luajit-2.1 /usr/local/include/lua5.1; do
    if [ -f "$dir/lua.h" ]; then
        LUA_INC="$dir"
        break
    fi
done

if [ -z "$LUA_INC" ]; then
    echo "ERROR: Lua/LuaJIT headers not found."
    echo "Install with: sudo apt install libluajit-5.1-dev  (or lua5.1-dev)"
    exit 1
fi

echo "Lua headers: $LUA_INC"

# Clone luasec
echo "Cloning luasec $LUASEC_VERSION..."
git clone --depth 1 --branch "$LUASEC_VERSION" https://github.com/brunoos/luasec.git "$TMP_DIR/luasec"

# Build
echo "Building luasec..."
cd "$TMP_DIR/luasec"

if [ "$OS" = "linux" ]; then
    make linux INC_PATH="-I$LUA_INC" LIB_PATH="" OPENSSL_LIBS="-lssl -lcrypto"
elif [ "$OS" = "macos" ]; then
    # Homebrew OpenSSL path
    OPENSSL_DIR="$(brew --prefix openssl 2>/dev/null || echo "/usr/local/opt/openssl")"
    make macosx INC_PATH="-I$LUA_INC -I$OPENSSL_DIR/include" LIB_PATH="-L$OPENSSL_DIR/lib"
fi

# Install into lib/
echo "Installing into $LIB_DIR..."
mkdir -p "$LIB_DIR/ssl"

# The compiled C module
cp src/ssl.so "$LIB_DIR/ssl.so"

# The pure-Lua wrapper files
cp src/ssl.lua "$LIB_DIR/ssl.lua"
cp src/https.lua "$LIB_DIR/ssl/https.lua"

echo ""
echo "=== luasec setup complete ==="
echo "Installed:"
echo "  $LIB_DIR/ssl.so"
echo "  $LIB_DIR/ssl.lua"
echo "  $LIB_DIR/ssl/https.lua"
