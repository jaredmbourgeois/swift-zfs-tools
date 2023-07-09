#!/bin/bash
SWIFT=/usr/share/swift/usr/bin/swift

CONFIG="release"
if [[ "$1" == "--config="* ]]; then
    CONFIG="${1#*=}"
fi
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
"$SWIFT" build --build-path "$PROJECT_DIR/build" -c "$CONFIG"
cp "$PROJECT_DIR/build/x86_64-unknown-linux-gnu/$CONFIG/ZFSTools" "$PROJECT_DIR/bin/linux-x86_64/zfs-tools"
