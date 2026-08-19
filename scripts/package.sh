#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
APP_DIR="$ROOT_DIR/dist/SparkTPS.app"

cd "$ROOT_DIR"
swift build -c release --arch arm64

mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$ROOT_DIR/.build/arm64-apple-macosx/release/SparkTPS" "$APP_DIR/Contents/MacOS/SparkTPS"
cp "$ROOT_DIR/Packaging/Info.plist" "$APP_DIR/Contents/Info.plist"
codesign --force --deep --sign - "$APP_DIR"

echo "$APP_DIR"
