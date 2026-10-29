# Changelog

## Unreleased

- A display show wakes the display, holds a wake assertion until clear or shutdown, reconnects the configured AirPlay receiver when its screen is missing, and sets `verified` only when the agent's window is full screen on that screen with a matching hash. A failed step is named and the window is not moved to another screen. `--dry-run` does not wake, reconnect, or show.
- `home blink --accessory --times --interval` blinks a light and restores its prior state.
- `display layout` renders a JSON module spec on a 16:9 canvas. Modules are header, message, columns, list, summary, and alert. Themes are separate from layout. `default` and `moonlit-autumn` ship with the package.
- `html`, `image`, and `video` modules fill a layout slot. Local image and video files are embedded as data URLs. Empty html or src is an error.

## 0.1.0

- CLI `home-signal` with JSON output, exit codes, `--dry-run`, and `describe`.
- `HomeSignalAgent` Unix socket server, simulated devices, and macOS hooks for HomeKit, a borderless signal window, Control Center mirroring, pointer events, and screenshots.
- Pluggable light backends: HomeKit (when the SDK imports it), Shortcuts, HTTP, and simulated.
