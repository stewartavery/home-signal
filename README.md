# home-signal

`home-signal` is a macOS command-line tool for AI agents. It controls HomeKit lights and scenes, and it sends household signals: a full-screen page on a TV, a light blink, or both. A background agent owns the slow resources. The CLI is a thin client over a local Unix socket.

The default Swift package builds on Linux and macOS. HomeKit, the signal window, AirPlay, pointer events, and screenshots need a Mac. Unit tests cover config, rendering, geometry, blink-and-restore, IPC, and the CLI without those frameworks.

## Layout

| Piece | Role |
| --- | --- |
| `home-signal` | CLI. Parses commands, prints JSON, exits with a stable code. |
| `HomeSignalAgent` | Long-running process. Menu-bar item on macOS (`LSUIElement` / accessory policy). |
| `HomeSignalCore` | Shared models, config, IPC, sockets. |
| `HomeSignalKit` | Request dispatch and blink-and-restore. |
| `HomeSignalLights`, `Display`, `Mirroring`, `Input`, `Capture` | Pluggable backends and signal channels. |

See [ARCHITECTURE.md](ARCHITECTURE.md) for how to add a backend or a channel.

## Install

On a Mac with Swift 6:

```bash
swift build -c release
Scripts/install.sh
```

That installs `home-signal` into `~/.local/bin` (override with `PREFIX` or `BIN_DIR`) and wraps `HomeSignalAgent` in an app bundle under `~/Applications` so it stays out of the Dock. The script does not use sudo. If that directory is not on `PATH`, it prints the `export` line to add. You can also run the built binaries directly.

```bash
HomeSignalAgent            # real devices and macOS UI
HomeSignalAgent --simulate # in-memory devices, no HomeKit or UI
home-signal daemon status
```

Write a config once:

```bash
home-signal config init
# edit ~/.config/home-signal/config.toml
```

The example file uses placeholders (`TV`, `Lamp 1`, `Room A`, 1920×1080). Replace them with names from your Home app and with sizes from `home-signal displays`.

## Permissions

The agent needs these macOS permissions, granted to `HomeSignalAgent` (or the app bundle):

| Permission | Used for |
| --- | --- |
| HomeKit | Reading and setting lights and scenes. Also requires the entitlement below. |
| Accessibility | Control Center clicks and `CGEvent` pointer events. |
| Automation | System Events controlling Control Center. |
| Screen Recording | `screenshot` via ScreenCaptureKit. |

### HomeKit entitlement

`homekit.backend = "homekit"` only starts when this process is signed with `com.apple.developer.homekit`. Apple issues that entitlement for a Mac Catalyst or iOS app, not for this menu-bar agent or a command-line binary. The agent checks `codesign` at startup and refuses with exit 6 when the entitlement is missing, instead of opening HomeKit and failing later.

The working path on this agent is `shortcuts` or `http`:

```toml
[homekit]
backend = "shortcuts"
```

`HomeKitLightBackend` remains in the package for a separate Mac Catalyst app that you sign with the entitlement. The sample plist under `Apps/` has `NSHomeKitUsageDescription`. A default `swift build` of this repo does not produce that signed app.

## Commands

Every command accepts `--json` (envelope on stdout), `--dry-run` (mutating commands do not change devices, the window, mirroring, or the pointer; a display dry-run does not wake, reconnect, or show), `--config`, and `--socket`. Flags may appear before or after the subcommand. `home-signal describe --json` prints the manifest. `home-signal <command> --help` documents that command.

Exit codes: `0` success, `1` usage, `2` config, `3` not found, `4` backend failure, `5` agent is down, `6` unsupported or missing permission, `7` timeout, `8` blink could not restore the prior state, `64` invalid command line.

```bash
home-signal --json device list
home-signal --json device get "Lamp 1"
home-signal --json device set "Lamp 1" --on --brightness 40 --color warm
home-signal --json --dry-run device blink "Lamp 1" --times 3 --color amber
home-signal --json scene list
home-signal --json scene run "Scene A"

home-signal display message "Example notice" --target "TV"
home-signal --dry-run display message "Example notice"
home-signal display schedule --title "Example day" \
  --row "09:00|Example item" \
  --row "12:30|Example meeting"
home-signal display layout --file ./spec.json
home-signal display layout --theme moonlit-autumn --spec '{"title":"Reminder","theme":"default","modules":[{"type":"message","text":"Example reminder"}]}'
home-signal display html --file ./page.html
home-signal display clear

home-signal displays
home-signal mirror list
home-signal mirror list --discover --debug-ax
home-signal mirror status --target "TV"
home-signal mirror connect --target "TV" --mode window
home-signal mirror disconnect --target "TV"

home-signal input park
home-signal input click 100 100 --clicks 2
home-signal screenshot --display main --out /tmp/signal.png

home-signal home blink --accessory "Lamp 1" --times 3 --interval 0.4
home-signal --dry-run home blink --accessory "Lamp 1" --times 1 --interval 0.5
```

`device set` writes only the fields you pass. `device blink` reads power, brightness, hue, saturation, and color temperature, blinks, writes that snapshot back, and reads the light again. A mismatch exits 8.

`home blink --accessory NAME --times N --interval SECONDS` does the same restore for one accessory. `--interval` is the seconds the light stays on and the seconds it stays off between blinks (0.05 to 10). The name has to be a light from `device list`. A missing accessory exits 3. An accessory that is not a light exits 6 (`not_controllable`). `--dry-run` reads the prior state and does not write.

`display message`, `display schedule`, `display layout`, and `display html` do not invent a page. Empty text, an empty or invalid layout spec, a missing HTML argument, or an empty file exits 1 and leaves the current page alone. `display html` loads the file or string unchanged; it is not wrapped in a template. `display layout` renders a module spec to HTML and shows those bytes through the same read-back.

A show then wakes the display and holds a no-display-sleep assertion (the same idea as `caffeinate -d`) until `display clear` or the agent exits. It checks that the AirPlay receiver is attached. The receiver name and id come from `mirror.target` and `mirror.device_id`, or from `--target` and `--device-id` on that command. Those values are configuration, not names built into the tool. If that screen is missing, the agent reconnects it the same way as `mirror connect` and waits up to `display.reconnect_seconds`. The agent's own window is placed full screen on that screen. `verified` is true only when the SHA-256 and title match, the window's screen is that receiver, and the window covers that screen. Otherwise the command exits non-zero. The error names the failed step: `wake`, `reconnect`, `place`, or `verify`. A hash mismatch uses code `display_mismatch` and step `verify`. The window is not moved to another screen, and a failure does not substitute a placeholder page. `--dry-run` reports whether the receiver is attached and does not wake, reconnect, or show. `display clear` hides the window and releases the assertion. Its `verified` field is false because no page is confirmed.

The JSON result includes `contentHash`, `title`, `verified`, `target`, `screen`, `fullScreen`, `onTarget`, and `holdingWake`. A layout result also includes `html`.

## Display layout

`display layout` takes a JSON spec and paints it on a fixed 16:9 canvas. Modules are equal rows. Adding or removing one resizes the rest, so the canvas stays full. Pass `--file` or `--spec`, not both. `--theme` overrides the spec. Built-in themes are `default` (neutral) and `moonlit-autumn`. Omit `theme` to use `default`. An unknown theme, unknown module, or blank field is an error.

Screenshots, the command flow, the module catalog, and the token scale are in [docs/display-layout.md](docs/display-layout.md).

The stage padding is the `xl` space token. Module rows use a grid with `gap: var(--space-l)` and `grid-auto-rows: minmax(0, 1fr)`. Each block is a flex column with `flex: 1`. A `columns` module lays its sections on a grid with the same gap. Text starts at a type token and steps down that scale when it would overflow.

Type tokens use a 1.5 ratio between steps. `xl` is 8vh and `xxl` is 12vh (1.5 times `xl`).

| Token | CSS | Size |
| --- | --- | --- |
| xs | `--type-xs` | 1.6vh |
| s | `--type-s` | 2.4vh |
| m | `--type-m` | 3.6vh |
| l | `--type-l` | 5.4vh |
| xl | `--type-xl` | 8vh |
| xxl | `--type-xxl` | 12vh |

| Token | CSS | Size | Role |
| --- | --- | --- | --- |
| xs | `--space-xs` | 0.8vh | |
| s | `--space-s` | 1.6vh | |
| m | `--space-m` | 2.4vh | |
| l | `--space-l` | 4vh | Grid gap |
| xl | `--space-xl` | 6vh | Page margin |

Default primary sizes: header title `xl`, message `xxl`, column items `s`, list items `m`, summary value `xl`, alert text `l`. Labels use `s`. Section headings use `m`. Set `size` on a module to override its primary text (`xs`, `s`, `m`, `l`, `xl`, `xxl`).

| Module | Required | Optional |
| --- | --- | --- |
| `header` | `title` | `subtitle`, `size` |
| `message` | `text` | `size` |
| `columns` | `columns[].items` | `columns[].title`, `size` |
| `list` | `items` | `title`, `size` |
| `summary` | `label`, `value` | `detail`, `size` |
| `alert` | `text` | `title`, `level` (`info`, `warning`, `critical`), `size` |
| `html` | `html` | |
| `image` | `src` | `fit` (`contain` or `cover`, default `contain`), `caption` |
| `video` | `src` | `fit` (`contain` or `cover`, default `contain`), `caption`, `autoplay`, `muted`, `loop` |

`html`, `image`, and `video` fill one grid slot the same way as the other blocks (`flex: 1`, the page gap, and the stage margin). The slot clips its content. An empty `html` or `src` is an error.

`html` places the string in that slot as its own document. The markup is not sanitized or rewritten. Styles and tags inside it stay in the slot.

`src` may be an `http`, `https`, or `data` URL. A local path or `file` URL is embedded as a data URL so the signal window can load it without a separate server. Image files: png, jpeg, gif, webp, svg, bmp, avif. Video files: mp4, webm, ogg, mov. A missing file, an empty file, or an unknown type is an error. Paths in a spec file are relative to that file. Paths in `--spec` are relative to the current directory.

Video defaults are `autoplay`, `muted`, and `loop`. Set any of them to `false` to override that one flag. The video stays inline in the slot.

An item is an object with `text` and optional `leading`, or a string used as `text`. `title` on the spec is the document title. The read-back compares it to the window title. It is not drawn unless a module includes it.

Themes set color and font only. Layout and modules read CSS variables (`--background`, `--foreground`, `--muted`, `--accent`, `--surface`, `--alert`, `--alert-foreground`, `--font`). Add a theme by appending a `DisplayTheme` to `DisplayThemes.all`. Add a module by extending `DisplayModuleKind`, the spec parser, and `DisplayModuleHTML`.

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

Caller HTML in a slot:

```json
{ "type": "html", "html": "<p>Example notice</p>" }
```

Image, with an optional caption. `fit` defaults to `contain`:

```json
{ "type": "image", "src": "https://example.com/example.png", "fit": "contain", "caption": "Example" }
```

Video. `autoplay`, `muted`, and `loop` default to true:

```json
{ "type": "video", "src": "https://example.com/example.mp4", "fit": "cover", "autoplay": true, "muted": true, "loop": true }
```

`mirror list` prints the Screen Mirroring names Control Center shows. `--discover` also prints AirPlay instance names from `dns-sd -B _airplay._tcp`. `--debug-ax` writes the accessibility tree for each step to stderr, and `--debug-ax-file` writes that same text to a file.

Screen Mirroring is opened from a top-level menu bar item when Control Center has one. Otherwise the agent opens the Control Center menu bar item and clicks the module whose accessibility identifier is `controlcenter-screen-mirroring`. A description of `toggle button` is not that module, and the first toggle is not used. After that click, the agent polls up to 8 seconds for at least one checkbox inside `screen-mirroring-device-list`. `screen-mirroring-preferences` is not a receiver. The row identifier looks like `screen-mirroring-device-AirPlay:<id>` and is not the receiver name. The name is read from the row's attributes and children (`AXTitle`, `AXLabel`, `AXAttributedDescription`, `AXHelp`, `AXValue`, `AXCustomContent`, and nested static text). If those are generic, names are paired with visible labels in row order. `missing value`, `toggle button`, and `button` are never names. The checkbox value is the connection state. Names are matched after Unicode normalization (apostrophes, NFC, case, and whitespace). An exact name wins over a copy such as `Example TV (2)`. If no name is exposed, the command exits with the row order and identifiers. `--debug-ax` prints every attribute on each row. If Accessibility or Automation is missing (`-1743`, `-25211`, `-10006`, or an assistive-access or authorization denial), the command exits 6 with code `permission`. A missing Control Center window (`-1719`, invalid index) is code `not_ready` and exits 7. The menu bar item toggles the panel, so the agent waits for the window and clicks again when the first click closed it. The panel is closed when the command finishes.

`mirror list --backend auto` tries a non-UI media route first (`AVFoundation` / `MediaRemote`, loaded at runtime) and uses Control Center only when that route cannot answer and the screen is unlocked. `--backend routing` never opens Control Center. `--backend controlcenter` is the UI path. While the screen is locked, a command that would need Control Center exits 6 with code `screen_locked`. The media layer can list devices and, when a screen-mirroring context exists, connect the display. If the process only finds audio and video playback contexts, connect exits 6 with code `screen_mirror_unavailable` instead of pretending the display was mirrored. `--debug` prints the classes, selectors, and devices that were found.

While the Mac is locked and still logged in:

```bash
home-signal --json mirror list --backend routing --debug
home-signal --json mirror list --backend auto --debug
home-signal --json mirror connect --backend routing --target "TV" --debug
home-signal --json mirror list --backend controlcenter
```

The last command should fail with `screen_locked`. The routing list should not open Control Center.

`mirror connect` is a no-op when the target is already selected (`changed: false`). Disconnect behaves the same when it is already off. Showing a page reconnects that target when its screen is not attached. A second show does not reconnect while the screen is still attached.

`--dry-run` on `mirror connect` still opens Control Center to read the checkbox. It does not click the target or the window-mode points.

## Config

Path: `~/.config/home-signal/config.toml` (version 1). Socket default: `~/.local/share/home-signal/agent.sock`.

```toml
[homekit]
backend = "homekit"   # homekit | shortcuts | http | simulated

[display]
reconnect_seconds = 15   # how long a show waits for the receiver screen

[mirror]
target = "TV"         # AirPlay name. Must match the attached screen name.
device_id = ""        # optional. Matches a screen id, or the Control Center id when reconnecting.
mode = "window"       # window | display

[mirror.clicks]
# Fractions of the Screen Mirroring panel. Tune these on the Mac you use.
choose_content = { x = 0.50, y = 0.78 }
window_or_app = { x = 0.50, y = 0.55 }
mirror_this_window = { x = 0.50, y = 0.42 }
```

`[[displays]]` entries are in points, top-left origin, y downward (the same space as `CGEvent`). On macOS the agent probes attached screens and uses those frames. Config names are kept when the origin matches. If probing is unavailable, the config values are the fallback. Optional `[mirror.absolute]` points are used only when the panel frame cannot be read.

Simulated devices and scenes live under `[simulated]`. `HomeSignalAgent --simulate` uses them and does not touch HomeKit. It also treats `mirror.target` as an attached screen and does not wake the display or open a window. Use `--dry-run` on a real agent when you need the plan without showing a page.

## Shortcuts backend

macOS has no general HomeKit CLI. The `shortcuts` backend runs five Shortcuts by name (override the names in config). Each must take its input from Shortcut Input, must not show alerts, and must end in **Stop and Output** with plain text.

The built-in **Get the state of Home** action cannot take the accessory as a variable. Each shortcut needs one branch per accessory you want agents to control. The sample below uses the placeholder name `Lamp 1`; duplicate the branch for each real accessory.

### HomeSignal Get State

Input: accessory name as text. Output: one JSON object.

```json
{"name":"Lamp 1","power":true,"brightness":40,"hue":30,"saturation":80,"colorTemperatureKelvin":null}
```

1. Receive Shortcut Input as text.
2. If the text is exactly `Lamp 1`, add **Get the state of Home** for that accessory, once each, for Power State, Brightness, Hue, Saturation, and Color Temperature (skip a characteristic the accessory does not have).
3. Build the JSON with a Text action. Color temperature from HomeKit is in mireds; convert to Kelvin with `1000000 / mireds` before putting it in `colorTemperatureKelvin`.
4. Otherwise, Stop and Output `{"error":"unknown accessory"}`.

### HomeSignal Set State

Input: JSON `{"name","patch"}` where `patch` may include `power`, `brightness`, `hue`, `saturation`, `colorTemperatureKelvin`, and clear flags. Output: the same JSON shape as Get State.

**Control Home** binds a specific accessory and often cannot set a numeric hue. If the shortcut cannot apply a field, Stop and Output `{"error":"..."}`. The blink path then fails instead of leaving the wrong color in place. The HomeKit framework backend can write the numeric characteristics; prefer it when the entitlement is available.

### HomeSignal List Devices

No input. Output: `[{"name":"Lamp 1","room":"Room A","type":"light"}]`.

### HomeSignal List Scenes

No input. Output: `[{"name":"Scene A"}]`.

### HomeSignal Run Scene

Input: scene name as text. Output: `{"name":"Scene A","ran":true}`.

Run them once from the Shortcuts app so macOS records Automation permission for the terminal or agent.

## HTTP backend

`homekit.backend = "http"` calls a JSON service. Set `base_url` and `token_env` (a bearer token read from that environment variable). This is the extension point for Homebridge or any other bridge.

| Method | Path | Body |
| --- | --- | --- |
| `GET` | `/v1/devices` | |
| `GET` | `/v1/devices/{name}/state` | |
| `PUT` | `/v1/devices/{name}/state` | light patch JSON |
| `GET` | `/v1/scenes` | |
| `POST` | `/v1/scenes/{name}/run` | |

State JSON uses the same fields as Get State. Kelvin, not mireds.

## Verify on a Mac

These paths are not executed in CI:

- HomeKit get, set, blink, and read-back restore on a real accessory, including a bulb that was off and one that was in color-temperature mode.
- Shortcuts fallback, including a shortcut that returns `{"error":...}` when it cannot set a numeric hue.
- Menu-bar agent launch without a Dock icon, and the borderless signal window covering the target screen's full frame (the window does not use another screen when that one is missing).
- Display asleep and the AirPlay screen gone: `display message` wakes the display, reconnects the configured receiver, places the window full screen on that screen, and returns `verified: true`. If reconnect times out, the command exits 7, the error step is `reconnect`, and the page is not left on a local monitor.
- `display clear` hides the window and releases the wake assertion while the agent keeps running.
- `display message` twice changes the page and does not reconnect when the target screen is still attached.
- `display layout` on the signal window: one module fills the 16:9 canvas, and adding a module resizes the others without clipping the stage.
- `mirror status`, `connect`, and `disconnect` for an AirPlay target matched by name and, if you set it, by `device_id`.
- `home blink` on a real accessory, including one that was off, and a non-light name failing with `not_controllable` or `not_found`.
- Window mode: panel-fraction clicks land on Choose Content, Window or App, and Mirror This Window. Adjust `[mirror.clicks]` if they do not. System Events positions and `CGEvent` share a top-left origin; confirm that on the machine you use.
- A second display: probed origin and `input park --display <name>`.
- `screenshot` after Screen Recording permission, and pointer events after Accessibility permission.

## Develop

```bash
swift test
```

Swift 6 language mode. Linux runs the tests. The macOS job in CI builds the AppKit paths as well.
