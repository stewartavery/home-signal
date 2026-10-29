#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
swift build -c release
BIN_DIR="${BIN_DIR:-/usr/local/bin}"
mkdir -p "$BIN_DIR"
install -m 755 .build/release/home-signal "$BIN_DIR/home-signal"

APP_DIR="${APP_DIR:-$HOME/Applications}"
APP="$APP_DIR/HomeSignalAgent.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
install -m 755 .build/release/HomeSignalAgent "$APP/Contents/MacOS/HomeSignalAgent"
cp Apps/Info.plist "$APP/Contents/Info.plist"
echo "Installed home-signal to $BIN_DIR and $APP"
echo "Grant Accessibility, Automation, and Screen Recording to that app. See README.md for HomeKit signing."
