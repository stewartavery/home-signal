# AGENTS.md

`home-signal` lets a shell-driven agent control HomeKit lights and scenes and send signals (full-screen page, blink, AirPlay). The CLI talks to `HomeSignalAgent` over a Unix socket. Do not add personal names, accessory names, display sizes, or device identifiers to the repo. Those belong in the user's config or in a live `device list` / `displays` response.

## Commands

```bash
swift test
swift build
```

CI runs `swift test` on Linux and macOS. Linux cannot exercise HomeKit, AppKit, ScreenCaptureKit, or System Events. Do not claim those work without running them on a Mac.

## How to call the CLI

1. Start `HomeSignalAgent` (or `--simulate` when hardware is absent). If the socket is down, commands exit `5`.
2. Pass `--json` on every call. Parse the envelope: `ok`, `command`, `dryRun`, `data`, `error`.
3. Discover names. Do not invent them. `device list`, `scene list`, `displays`, and `mirror status --target` report what this machine can see. Config placeholders such as `Lamp 1` and `TV` are examples.
4. Use `--dry-run` before a mutating command when you only need the plan. Blink dry-run reads state and does not write. Mirror dry-run reads Control Center and does not click the target.
5. `device blink` must restore power, brightness, hue, saturation, and color temperature. Exit `8` means it did not. Read the light and fix it.
6. Show a page with `display message`, `display schedule`, or `display html --file`. Empty content is an error and must not be retried with a placeholder. Check `contentHash`, `title`, and `verified` in the result; `display_mismatch` means the screen is not the page you sent.
7. `home-signal describe --json` is the command manifest. `home-signal <command> --help` is the human text.

Exit codes: `0` ok, `1` usage, `2` config, `3` not found, `4` backend, `5` agent down, `6` unsupported or permission, `7` timeout, `8` restore failed, `64` bad command line.

Config: `~/.config/home-signal/config.toml`. Socket: `~/.local/share/home-signal/agent.sock`, or `--socket`.

## Code

- Swift 6, strict concurrency. Protocols in `HomeSignalCore`. The agent process is the composition root (`Sources/HomeSignalAgent/Boot.swift`).
- New device backends implement `LightBackend`. New signal outputs implement a channel protocol and a branch in `AgentRuntime`.
- Comment only a non-obvious platform constraint. No file banners and no comments that restate the code.
- Keep diffs small. `swift test` must pass before you finish.

## On a Mac, still verify

HomeKit numeric restore, Shortcuts branches, the borderless window, Control Center mirroring (including window-mode click fractions), pointer events, and screenshots. Details are in the README.
