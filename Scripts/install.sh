#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
swift build -c release

PREFIX="${PREFIX:-$HOME/.local}"
BIN_DIR="${BIN_DIR:-$PREFIX/bin}"
if ! mkdir -p "$BIN_DIR"; then
  echo "Cannot create $BIN_DIR." >&2
  echo "Set PREFIX to a directory you can write, for example: PREFIX=\"\$HOME/.local\" $0" >&2
  exit 1
fi
if ! install -m 755 .build/release/home-signal "$BIN_DIR/home-signal"; then
  echo "Could not install home-signal into $BIN_DIR." >&2
  echo "Set PREFIX to a directory you can write, for example: PREFIX=\"\$HOME/.local\" $0" >&2
  exit 1
fi

APP_DIR="${APP_DIR:-$HOME/Applications}"
APP="$APP_DIR/HomeSignalAgent.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
install -m 755 .build/release/HomeSignalAgent "$APP/Contents/MacOS/HomeSignalAgent"
cp Apps/Info.plist "$APP/Contents/Info.plist"
echo "Installed home-signal to $BIN_DIR/home-signal"
echo "Installed the agent to $APP"
case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *)
    echo "Add the command to PATH:"
    echo "  export PATH=\"$BIN_DIR:\$PATH\""
    ;;
esac
echo "Grant Accessibility, Automation, and Screen Recording to that app."
echo "This agent does not use HomeKit unless the binary is signed with com.apple.developer.homekit. Otherwise set homekit.backend to shortcuts or http. See README.md."
