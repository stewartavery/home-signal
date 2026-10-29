# Changelog

## Unreleased

- `display layout` renders a JSON module spec on a 16:9 canvas. Modules are header, message, columns, list, summary, and alert. Themes are separate from layout. `default` and `moonlit-autumn` ship with the package.
- `html`, `image`, and `video` modules fill a layout slot. Local image and video files are embedded as data URLs. Empty html or src is an error.
- `display proof export` writes self-contained layout HTML and content hashes without showing a page. Playwright checks the 1920×1080 grid in a pinned container. Linux Chromium goldens are recorded only there.

## 0.1.0

- CLI `home-signal` with JSON output, exit codes, `--dry-run`, and `describe`.
- `HomeSignalAgent` Unix socket server, simulated devices, and macOS hooks for HomeKit, a borderless signal window, Control Center mirroring, pointer events, and screenshots.
- Pluggable light backends: HomeKit (when the SDK imports it), Shortcuts, HTTP, and simulated.
