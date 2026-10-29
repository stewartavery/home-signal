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
4. Use `--dry-run` before a mutating command when you only need the plan. Blink dry-run reads state and does not write. Mirror dry-run reads Control Center and does not click the target. Display dry-run reads whether the target screen is attached and does not wake, reconnect, or show a page.
5. `device blink` and `home blink --accessory NAME --times N --interval SECONDS` must restore power, brightness, hue, saturation, and color temperature. Exit `8` means they did not. Read the light and fix it. `home blink` exits `3` when the accessory is missing and `6` when it is not a light. `homekit.backend = "homekit"` exits `6` unless the process is signed with `com.apple.developer.homekit`. Use `shortcuts` or `http` for this agent.
6. Show a page with `display message`, `display schedule`, `display layout`, or `display html --file`. Empty content is an error and must not be retried with a placeholder. The target is `mirror.target` / `mirror.device_id`, or `--target` / `--device-id` on the command. Do not invent a screen. A show wakes the display, holds a wake assertion until `display clear`, reconnects the receiver when its screen is missing, and places the agent's window full screen on that screen only. `verified` is true only when the window is on that screen, the window is full screen, and `contentHash` matches. Otherwise the command exits non-zero and the error names the step (`wake`, `reconnect`, `place`, or `verify`). `display_mismatch` is the verify step for a hash or title mismatch. Do not fall back to another screen or a placeholder page. `display html` shows caller HTML unchanged. `display layout` renders a JSON module spec and shows that HTML through the same read-back. The layout result also includes `html`.
7. `home-signal describe --json` is the command manifest. `home-signal <command> --help` is the human text.

### Display layout

```bash
home-signal --json display layout --file spec.json
home-signal --json display layout --spec '{"title":"Reminder","theme":"default","modules":[{"type":"message","text":"Example reminder"}]}'
home-signal --json display layout --theme moonlit-autumn --file spec.json
```

The spec needs `title` (document title), optional `theme` (`default` or `moonlit-autumn`; omit for `default`), and a non-empty `modules` array. Types are `header`, `message`, `columns`, `list`, `summary`, and `alert`. Pass `--file` or `--spec`, not both. An empty file, invalid JSON, unknown theme, unknown module, or blank text exits 1 and does not replace the page.

The canvas is 16:9. Module rows use `gap: var(--space-l)` and `grid-auto-rows: minmax(0, 1fr)`. Each block is `flex: 1`. A columns module uses a grid with the same gap. Text starts at a type token and steps down the scale when it would overflow.

Type tokens, vh, 1.5 ratio between steps (`xl` is 8vh, `xxl` is 12vh): `--type-xs` 1.6vh, `--type-s` 2.4vh, `--type-m` 3.6vh, `--type-l` 5.4vh, `--type-xl` 8vh, `--type-xxl` 12vh. Space tokens: `--space-xs` 0.8vh, `--space-s` 1.6vh, `--space-m` 2.4vh, `--space-l` 4vh (grid gap), `--space-xl` 6vh (page margin).

Required fields: header `title`; message `text`; columns `columns[].items`; list `items`; summary `label` and `value`; alert `text`; html `html`; image and video `src`. Items are `{ "leading", "text" }` or a string. Optional `size` is a type token. Alert `level` is `info`, `warning`, or `critical`. Image and video `fit` is `contain` (default) or `cover`. Video `autoplay`, `muted`, and `loop` default to true; set a flag to false to override it. Empty `html` or `src` is an error. `html` is shown unchanged inside its slot. A local image or video path is embedded as a data URL; `http`, `https`, and `data` URLs are used as given.

One-line reminder:

```json
{
  "title": "Reminder",
  "theme": "default",
  "modules": [
    {
      "type": "message",
      "text": "Example reminder"
    }
  ]
}
```

Multi-section schedule:

```json
{
  "title": "Example day",
  "theme": "moonlit-autumn",
  "modules": [
    {
      "type": "header",
      "title": "Example day",
      "subtitle": "Placeholder"
    },
    {
      "type": "columns",
      "columns": [
        {
          "title": "Morning",
          "items": [
            { "leading": "09:00", "text": "Example item" },
            { "leading": "10:30", "text": "Example item" }
          ]
        },
        {
          "title": "Afternoon",
          "items": [
            { "leading": "13:00", "text": "Example meeting" },
            { "leading": "16:00", "text": "Example item" }
          ]
        }
      ]
    },
    {
      "type": "summary",
      "label": "Next",
      "value": "Example item",
      "detail": "09:00"
    }
  ]
}
```

`html`, `image`, and `video` fill a grid slot like any other block (`flex: 1`, same gap and margin). Content stays inside the slot.

```json
{ "type": "html", "html": "<p>Example notice</p>" }
```

```json
{ "type": "image", "src": "https://example.com/example.png", "fit": "contain", "caption": "Example" }
```

```json
{ "type": "video", "src": "https://example.com/example.mp4", "fit": "cover", "autoplay": true, "muted": true, "loop": true }
```

Themes are color and font only (`DisplayThemes.all`). Add a module in `DisplayModuleKind`, the spec parser, and `DisplayModuleHTML`. Do not put colors in the layout CSS.

Exit codes: `0` ok, `1` usage, `2` config, `3` not found, `4` backend, `5` agent down, `6` unsupported or permission, `7` timeout, `8` restore failed, `64` bad command line.

Config: `~/.config/home-signal/config.toml`. Socket: `~/.local/share/home-signal/agent.sock`, or `--socket`.

## Code

- Swift 6, strict concurrency. Protocols in `HomeSignalCore`. The agent process is the composition root (`Sources/HomeSignalAgent/Boot.swift`).
- New device backends implement `LightBackend`. New signal outputs implement a channel protocol and a branch in `AgentRuntime`.
- Display wake, attached screens, and window placement go through `DisplayPowerControlling`, `AttachedDisplayListing`, and `DisplayPlacing`. Fakes cover those in tests. The macOS types are `IOKitDisplayPower`, `MacAttachedDisplays`, and `MacDisplayChannel`. A show must not call `NSScreen.main` when the target is missing.
- Comment only a non-obvious platform constraint. No file banners and no comments that restate the code.
- Keep diffs small. `swift test` must pass before you finish.

## On a Mac, still verify

HomeKit numeric restore only on a binary signed with the HomeKit entitlement; otherwise shortcuts or http. Control Center mirroring: top-level Screen Mirroring item when present, otherwise Control Center then the module identifier `controlcenter-screen-mirroring` (not the first toggle). Wait until `screen-mirroring-device-list` has a checkbox. Row identifiers are opaque; names come from attributes and children, never from `missing value`. `--debug-ax` prints every attribute on each row. The borderless window on the configured AirPlay screen (wake, reconnect when the screen is gone, full-screen frame, `verified` false when it is not that screen), releasing the wake assertion on `display clear`, window-mode click fractions, pointer events, and screenshots. Details are in the README.
