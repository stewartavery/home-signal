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
6. Show a page with `display message`, `display schedule`, `display layout`, or `display html --file`. Empty content is an error and must not be retried with a placeholder. Check `contentHash`, `title`, and `verified` in the result; `display_mismatch` means the screen is not the page you sent. `display html` shows caller HTML unchanged. `display layout` renders a JSON module spec and shows that HTML through the same read-back. The layout result also includes `html`.
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

Required fields: header `title`; message `text`; columns `columns[].items`; list `items`; summary `label` and `value`; alert `text`. Items are `{ "leading", "text" }` or a string. Optional `size` is a type token. Alert `level` is `info`, `warning`, or `critical`.

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

Themes are color and font only (`DisplayThemes.all`). Add a module in `DisplayModuleKind`, the spec parser, and `DisplayModuleHTML`. Do not put colors in the layout CSS.

### Display proof

Check layout changes without a display. `swift test` includes the fixture contract. The browser suite is separate:

```bash
scripts/display-proof.sh verify
scripts/display-proof.sh record
```

`verify` runs `swift test`, then Playwright in the image from `VisualProof/playwright-image.txt`. `record` rewrites fixture HTML with `display proof export` and runs container-only `--update-snapshots=changed`. Regen Linux goldens only in that container. Never record against a host browser or a real display. `display proof export` does not show a page and does not invent content when a spec is empty.

On a Mac, use the same scripts for Linux goldens (Docker runs the pinned linux/amd64 image). Optional WKWebView baselines are not part of CI. `HS_MAC_PROOF=record` writes them and `HS_MAC_PROOF=1` compares them. They live in `Fixtures/DisplayProof/screenshots/darwin` and must not be compared to `screenshots/linux`. Linux skips that smoke.

Add a fixture by putting a JSON spec in `Fixtures/DisplayProof/specs` and a row in `catalog.json`, then `scripts/display-proof.sh record`. Keep the catalog between 8 and 12 pages unless you are extending coverage on purpose. Placeholder copy only.

Exit codes: `0` ok, `1` usage, `2` config, `3` not found, `4` backend, `5` agent down, `6` unsupported or permission, `7` timeout, `8` restore failed, `64` bad command line.

Config: `~/.config/home-signal/config.toml`. Socket: `~/.local/share/home-signal/agent.sock`, or `--socket`.

## Code

- Swift 6, strict concurrency. Protocols in `HomeSignalCore`. The agent process is the composition root (`Sources/HomeSignalAgent/Boot.swift`).
- New device backends implement `LightBackend`. New signal outputs implement a channel protocol and a branch in `AgentRuntime`.
- Comment only a non-obvious platform constraint. No file banners and no comments that restate the code.
- Keep diffs small. `swift test` must pass before you finish.

## On a Mac, still verify

HomeKit numeric restore, Shortcuts branches, the borderless window, Control Center mirroring (including window-mode click fractions), pointer events, and screenshots. Details are in the README.
