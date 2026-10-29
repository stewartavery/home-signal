# Changelog

## Unreleased

- After the Control Center menu bar click, the agent waits up to 3 seconds for the window. If that click closed an already-open panel, it clicks again. Error -1719 (invalid index) is `not_ready`, not a permission failure. Permission remains -1743, -25211, -10006, and assistive-access or authorization denials. Control Center is closed at the end of every mirror command.
- Screen Mirroring is opened from a top-level menu bar item when one exists, otherwise from Control Center. The module click matches the identifier `controlcenter-screen-mirroring` and does not click the first toggle. Receiver rows are the checkboxes inside `screen-mirroring-device-list`, read after they appear (up to 8 seconds) rather than from `screen-mirroring-preferences`. The row identifier is opaque. Names come from the row's attributes and children, or from visible labels in row order. `missing value` is not a name. `--debug-ax` prints every attribute on each row. Names are normalized, copy suffixes such as ` (2)` match after exact names, and a miss lists the names that were read. Missing Accessibility or Automation exits 6. `mirror list` prints those names, with optional dns-sd discovery and `--debug-ax`.
- `Scripts/install.sh` installs into `~/.local/bin` unless `PREFIX` or `BIN_DIR` is set, and prints a PATH hint. It does not use sudo.
- `homekit.backend = "homekit"` is refused unless the process is signed with `com.apple.developer.homekit`. Use `shortcuts` or `http` for this agent.
- A display show wakes the display, holds a wake assertion until clear or shutdown, reconnects the configured AirPlay receiver when its screen is missing, and sets `verified` only when the agent's window is full screen on that screen with a matching hash. A failed step is named and the window is not moved to another screen. `--dry-run` does not wake, reconnect, or show.
- `home blink --accessory --times --interval` blinks a light and restores its prior state.
- `display layout` renders a JSON module spec on a 16:9 canvas. Modules are header, message, columns, list, summary, and alert. Themes are separate from layout. `default` and `moonlit-autumn` ship with the package.
- `html`, `image`, and `video` modules fill a layout slot. Local image and video files are embedded as data URLs. Empty html or src is an error.

## 0.1.0

- CLI `home-signal` with JSON output, exit codes, `--dry-run`, and `describe`.
- `HomeSignalAgent` Unix socket server, simulated devices, and macOS hooks for HomeKit, a borderless signal window, Control Center mirroring, pointer events, and screenshots.
- Pluggable light backends: HomeKit (when the SDK imports it), Shortcuts, HTTP, and simulated.
