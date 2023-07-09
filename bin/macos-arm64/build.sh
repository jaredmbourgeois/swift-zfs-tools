#!/bin/bash

CONFIG="release"
if [[ "$1" == "--config="* ]]; then
    CONFIG="${1#*=}"
fi
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
swift build --build-path "$PROJECT_DIR/build" -c "$CONFIG"
cp "$PROJECT_DIR/build/arm64-apple-macosx/$CONFIG/ZFSTools" "$PROJECT_DIR/bin/macos-arm64/zfs-tools"
