# Architecture

`home-signal` is a Swift package in Swift 6 mode. The CLI never talks to HomeKit directly. It sends one JSON request per invocation to `HomeSignalAgent` on a Unix socket and prints the response.

```
home-signal  --JSON-->  AgentServer  -->  AgentRuntime
                                              |-- LightBackend
                                              |-- DisplayChannel
                                              |-- MirrorChannel
                                              |-- InputChannel
                                              |-- CaptureChannel
```

## Modules

- `HomeSignalCore` — models, config (TOML version 1), IPC types, socket, logging. No device I/O.
- `HomeSignalKit` — `AgentRuntime` dispatches methods. `BlinkService` reads state, blinks, writes the prior state back, and checks the read-back.
- `HomeSignalLights` — `SimulatedLightBackend`, `ShortcutsLightBackend`, `HTTPLightBackend`, and `HomeKitLightBackend` (compiled only when HomeKit is importable).
- `HomeSignalDisplay` — HTML for the signal page, plus an AppKit borderless window on macOS.
- `HomeSignalMirroring` — panel geometry, the System Events script, and a native route stub. `AVRoutePickerView` cannot select a named target without a click, so the agent falls back to System Events.
- `HomeSignalInput` — `CGEvent` on macOS. Coordinates are computed from display frames, not stored as a particular machine's pixels.
- `HomeSignalCapture` — ScreenCaptureKit on macOS.
- `HomeSignalCLI` / `home-signal` — argument parsing and the JSON envelope.
- `HomeSignalAgent` — wires a backend and the channels, then serves the socket. On macOS it also installs a status item.

`HomeSignalAgent --simulate` uses the in-memory implementations so the same request path runs under `swift test` on Linux.

## IPC

Protocol version 1. One connection, one JSON object, then EOF.

```json
{"protocolVersion":1,"id":"...","method":"lights.get","params":{"name":"Lamp 1"},"dryRun":false}
```

Responses echo `id` and set `ok`. Errors carry `code`, `message`, `hint`, and `exitCode`. `capabilities` lists methods and the active backend id. Unknown protocol versions are rejected.

Logging goes through `os.Logger` when it exists, and to stderr otherwise. The subsystem is `home-signal`.

## Config

`ConfigLoader` reads a small TOML subset (version 1): tables, arrays of tables, inline tables, strings, numbers, and bools. Missing keys use the built-in placeholders. Device names, the AirPlay target, display rectangles, and click fractions are data, not constants in command code.

On macOS, `MacDisplayProbe` replaces display rectangles with `NSScreen` frames converted from Cocoa's bottom-left origin into the top-left space used by `CGEvent` and System Events. Config names are applied when the origin matches.

## Add a device backend

1. Implement `LightBackend` in `HomeSignalLights` (or a new target that the agent links).
2. Add a `homekit.backend` value in `ConfigLoader`'s allow-list.
3. Construct it in `makeLights` in `Sources/HomeSignalAgent/Boot.swift`.
4. Cover list/get/set/scenes with a fake `CommandRunning` or `HTTPSending` if the backend talks to a process or URL. Blink-and-restore stays in `BlinkService` and should not be reimplemented.

HomeKit writes numeric characteristics and converts color temperature between Kelvin (the IPC value) and mireds (the characteristic). Shortcuts cannot always set a numeric hue; that backend must surface an error rather than report success.

## Add a signal channel

1. Add a protocol next to `DisplayChannel` if the output is a new kind of effect.
2. Add an `IPCMethod` and a `params` struct in `HomeSignalCore`.
3. Handle it in `AgentRuntime.dispatch`. Honor `dryRun` before any side effect that is not a read.
4. Add a CLI subcommand whose `--help` text states whether it is idempotent, and add a row to `CommandCatalog`.
5. Provide a simulated implementation and a test that runs CLI → socket → runtime without macOS.

`display html` passes caller markup through unchanged. `display layout` renders a JSON module spec to HTML in `DisplayLayout`, then shows those bytes with kind `layout`. `DisplayRendering` rejects an empty message, schedule, layout, or HTML document before anything is shown.

`DisplaySession` runs a show: wake and hold (`DisplayPowerControlling`), require the configured receiver in `AttachedDisplayListing` or reconnect through `MirrorChannel` until `display.reconnect_seconds`, then `DisplayPlacing` puts the agent's window full screen on that screen. `verified` is true only when the hash and title match, the reported screen is the matched screen, and the window is full screen. A failure names the step and does not place the window on a different screen. `--dry-run` only reads the attached list. `display clear` and agent shutdown dismiss the window and release the assertion. `HomeSignalAgent --simulate` treats the configured target as attached and uses in-memory fakes, so it does not wake hardware or open a window.

## Display layout

`DisplayTokens` is the type and space scale (vh). `DisplayThemes` is color and font. `DisplayLayout` paints a 16:9 stage, a grid of blocks (`gap` is `--space-l`, each block `flex: 1`), and the module markup. Modules are `header`, `message`, `columns`, `list`, `summary`, `alert`, `html`, `image`, and `video`. Text uses a type token and steps down that scale when the block would overflow. Caller HTML is framed in its slot. Local image and video paths are embedded as data URLs at render time.

Add a theme by appending a `DisplayTheme` to `DisplayThemes.all`. Add a module by extending `DisplayModuleKind`, validation in the spec parser, and `DisplayModuleHTML`. Layout CSS reads tokens and theme variables. It does not name a theme.

Channels that exist today: lights, scenes, display, mirror, input, capture.
