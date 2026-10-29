import ArgumentParser
import Foundation
import HomeSignalCore

struct Root: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "home-signal",
        abstract: "Control HomeKit devices and send household signals from the shell.",
        discussion: """
        home-signal is a thin client. Start HomeSignalAgent first; it owns HomeKit, \
        the full-screen signal window, AirPlay mirroring, pointer events, and screenshots. \
        The client talks to the agent over a Unix socket.

        Global options can appear before or after the subcommand:
          --json       JSON envelope on stdout
          --dry-run    Report mutating actions without performing them
          --config     Config file (default ~/.config/home-signal/config.toml)
          --socket     Agent socket

        Exit codes:
          0  success, including --help and --dry-run
          1  usage error
          2  config error
          3  device, scene, display, or AirPlay target not found
          4  backend or shortcut failure
          5  agent is not running
          6  unsupported on this build, or a permission is missing
          7  timed out
          8  a blink could not restore the prior light state
          64 invalid command line

        Device names, the AirPlay target, and display geometry come from the config file \
        or from discovery (`device list`, `displays`). The example config uses placeholders only.
        """,
        version: HomeSignalVersion.current,
        subcommands: [
            DescribeCommand.self,
            VersionCommand.self,
            ConfigCommand.self,
            DaemonCommand.self,
            CapabilitiesCommand.self,
            DeviceCommand.self,
            SceneCommand.self,
            DisplayCommand.self,
            MirrorCommand.self,
            InputCommand.self,
            ScreenshotCommand.self,
            DisplaysCommand.self,
        ]
    )
}

struct DescribeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "describe",
        abstract: "Print a machine-readable manifest of commands, flags, and exit codes."
    )
    @OptionGroup var global: GlobalOptions

    func run() throws {
        CLIRuntime.succeed(command: "describe", global: global, value: try CommandCatalog.manifest.jsonValue())
    }
}

struct VersionCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "version",
        abstract: "Print the CLI version and IPC protocol version."
    )
    @OptionGroup var global: GlobalOptions

    func run() throws {
        let payload: [String: JSONValue] = [
            "version": .string(HomeSignalVersion.current),
            "protocolVersion": .int(HomeSignalVersion.protocolVersion),
        ]
        CLIRuntime.succeed(command: "version", global: global, value: .object(payload))
    }
}

struct ConfigCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "config",
        abstract: "Show, locate, or write the config file.",
        subcommands: [ConfigShow.self, ConfigPath.self, ConfigInit.self]
    )
}

struct ConfigShow: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "show", abstract: "Print the effective configuration.")
    @OptionGroup var global: GlobalOptions
    func run() throws {
        let config = try CLIRuntime.load(global)
        CLIRuntime.succeed(command: "config.show", global: global, value: try config.jsonValue())
    }
}

struct ConfigPath: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "path", abstract: "Print the config path that would be read.")
    @OptionGroup var global: GlobalOptions
    func run() throws {
        let path = HomeSignalPaths.expand(global.config ?? HomeSignalPaths.configPath())
        CLIRuntime.succeed(command: "config.path", global: global, value: .object(["path": .string(path)]))
    }
}

struct ConfigInit: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "init",
        abstract: "Write the example config if the file does not already exist.",
        discussion: "Existing files are left unchanged. Edit names, displays, and the AirPlay target before controlling a real home."
    )
    @OptionGroup var global: GlobalOptions
    func run() throws {
        let path = HomeSignalPaths.expand(global.config ?? HomeSignalPaths.configPath())
        let existed = FileManager.default.fileExists(atPath: path)
        if !existed && !global.dryRun {
            let parent = (path as NSString).deletingLastPathComponent
            try FileManager.default.createDirectory(atPath: parent, withIntermediateDirectories: true)
            try Data(ConfigText.example.utf8).write(to: URL(fileURLWithPath: path))
        }
        CLIRuntime.succeed(
            command: "config.init",
            global: global,
            value: .object(["path": .string(path), "created": .bool(!existed && !global.dryRun), "existed": .bool(existed)])
        )
    }
}

struct DaemonCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "daemon",
        abstract: "Check or stop the background agent.",
        subcommands: [DaemonStatus.self, DaemonStop.self]
    )
}

struct DaemonStatus: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "status", abstract: "Ping the agent. Exit 5 when it is not running.")
    @OptionGroup var global: GlobalOptions
    func run() async throws {
        try await IPCCall.perform(global: global, command: "daemon.status", method: IPCMethod.systemPing)
    }
}

struct DaemonStop: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "stop",
        abstract: "Ask the agent to close its socket and exit.",
        discussion: "Idempotent from the client's point of view only while the agent is up. --dry-run does not stop it."
    )
    @OptionGroup var global: GlobalOptions
    func run() async throws {
        if global.dryRun {
            CLIRuntime.succeed(command: "daemon.stop", global: global, value: .object(["running": .bool(true), "stopped": .bool(false)]))
            return
        }
        try await IPCCall.perform(global: global, command: "daemon.stop", method: IPCMethod.systemShutdown)
    }
}

struct CapabilitiesCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "capabilities",
        abstract: "Ask the running agent which methods and device backend it has."
    )
    @OptionGroup var global: GlobalOptions
    func run() async throws {
        try await IPCCall.perform(global: global, command: "capabilities", method: IPCMethod.capabilities)
    }
}

struct DisplaysCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "displays",
        abstract: "List displays the agent will use for pointer, capture, and the signal window.",
        discussion: "On macOS the agent probes attached screens and uses those point sizes. Config entries supply names when the origin matches, and they are the fallback when probing is unavailable."
    )
    @OptionGroup var global: GlobalOptions
    func run() async throws {
        try await IPCCall.perform(global: global, command: "displays", method: IPCMethod.displaysList)
    }
}

struct DeviceCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "device",
        abstract: "List, read, set, or blink HomeKit lights.",
        subcommands: [DeviceList.self, DeviceGet.self, DeviceSet.self, DeviceBlink.self]
    )
}

struct DeviceList: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "List lights the current backend can see.")
    @OptionGroup var global: GlobalOptions
    func run() async throws {
        try await IPCCall.perform(global: global, command: "device.list", method: IPCMethod.lightsList)
    }
}

struct DeviceGet: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "get",
        abstract: "Read power, brightness, hue, saturation, and color temperature.",
        discussion: "Idempotent. Color temperature is Kelvin. Missing fields mean the accessory did not report them."
    )
    @OptionGroup var global: GlobalOptions
    @Argument(help: "Light name, exactly as the backend reports it.")
    var name: String
    func run() async throws {
        try await IPCCall.perform(global: global, command: "device.get", method: IPCMethod.lightsGet, params: try LightNameParams(name: name).jsonValue())
    }
}

struct DeviceSet: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "set",
        abstract: "Change one or more light fields.",
        discussion: """
        Omitted fields stay as they are. --color selects a named color (red, orange, amber, \
        yellow, green, cyan, blue, purple, pink, white, warm, cool) and clears the other color mode. \
        --dry-run reads the light and prints the state that would be written. Setting the same state again is safe.
        """
    )
    @OptionGroup var global: GlobalOptions
    @Argument(help: "Light name.") var name: String
    @Flag(name: .long, help: "Turn the light on.") var on = false
    @Flag(name: .long, help: "Turn the light off.") var off = false
    @Option(name: .long, help: "Brightness from 0 to 100.") var brightness: Int?
    @Option(name: .long, help: "Hue from 0 to 360.") var hue: Double?
    @Option(name: .long, help: "Saturation from 0 to 100.") var saturation: Double?
    @Option(name: .customLong("color-temperature"), help: "Color temperature in Kelvin.") var colorTemperature: Int?
    @Option(name: .long, help: "Named color. See the discussion.") var color: String?

    func run() async throws {
        if on && off { throw HomeSignalError.usage("Pass only one of --on or --off.") }
        let patch = LightPatch(
            power: on ? true : (off ? false : nil),
            brightness: brightness,
            hue: hue,
            saturation: saturation,
            colorTemperatureKelvin: colorTemperature,
            color: color
        )
        try await IPCCall.perform(
            global: global,
            command: "device.set",
            method: IPCMethod.lightsSet,
            params: try LightSetParams(name: name, patch: patch).jsonValue()
        )
    }
}

struct DeviceBlink: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "blink",
        abstract: "Blink a light, then restore its exact prior state.",
        discussion: """
        The agent reads power, brightness, hue, saturation, and color temperature first. \
        It then turns the light on in --color, off, and repeats. After the last off it writes the prior state back \
        and reads the light again. Exit 8 means the read-back did not match. \
        --dry-run only reads and returns that prior state. Default color is amber, three times.
        """
    )
    @OptionGroup var global: GlobalOptions
    @Argument(help: "Light name.") var name: String
    @Option(name: .long, help: "How many on/off cycles. From 1 to 30.") var times: Int = 3
    @Option(name: .long, help: "Named color used while the light is on.") var color: String = "amber"
    @Option(name: .customLong("on-ms"), help: "Milliseconds the light stays on.") var onMS: Int = 400
    @Option(name: .customLong("off-ms"), help: "Milliseconds the light stays off between cycles.") var offMS: Int = 250

    func run() async throws {
        let params = BlinkParams(name: name, times: times, color: color, onMilliseconds: onMS, offMilliseconds: offMS)
        try await IPCCall.perform(global: global, command: "device.blink", method: IPCMethod.lightsBlink, params: try params.jsonValue())
    }
}

struct SceneCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "scene",
        abstract: "List or run HomeKit scenes.",
        subcommands: [SceneList.self, SceneRun.self]
    )
}

struct SceneList: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "List scenes.")
    @OptionGroup var global: GlobalOptions
    func run() async throws {
        try await IPCCall.perform(global: global, command: "scene.list", method: IPCMethod.scenesList)
    }
}

struct SceneRun: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Run a scene by name.",
        discussion: "Not idempotent: running a scene applies whatever the scene contains. --dry-run does not run it."
    )
    @OptionGroup var global: GlobalOptions
    @Argument(help: "Scene name.") var name: String
    func run() async throws {
        try await IPCCall.perform(global: global, command: "scene.run", method: IPCMethod.scenesRun, params: try LightNameParams(name: name).jsonValue())
    }
}

struct DisplayCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "display",
        abstract: "Show a message, schedule, layout, or HTML page on the agent's full-screen window.",
        discussion: "Updating the window does not reconnect AirPlay. A show with no content fails and leaves the current page in place. `display layout` renders a JSON module spec into the 16:9 canvas. `display html` loads caller HTML unchanged. The JSON result includes the content hash and title read back from the window.",
        subcommands: [DisplayMessage.self, DisplaySchedule.self, DisplayLayoutCommand.self, DisplayHTML.self, DisplayClear.self, DisplayStatus.self]
    )
}

struct DisplayMessage: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "message",
        abstract: "Show centered text.",
        discussion: "The text argument is required. An empty string is an error and does not replace the page. Repeat the command to change the text in place. --no-present updates the page without ordering the window forward. The result includes contentHash, title, and verified."
    )
    @OptionGroup var global: GlobalOptions
    @Argument(help: "Text to show.") var text: String
    @Option(name: .long, help: "Optional heading above the message.") var title: String?
    @Flag(name: .customLong("no-present"), help: "Do not bring the window forward.") var noPresent = false

    func run() async throws {
        let config = try CLIRuntime.load(global)
        let doc = document(from: config, kind: DisplayKind.message, title: title, message: text, rows: [])
        _ = try DisplayRendering.prepare(doc)
        let params = DisplayShowParams(document: doc, present: !noPresent)
        try await IPCCall.perform(global: global, command: "display.message", method: IPCMethod.displayShow, params: try params.jsonValue())
    }
}

struct DisplaySchedule: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "schedule",
        abstract: "Show a title and rows of time and label.",
        discussion: "Pass one --row \"09:00|Example\" per line. Labels that contain | can be sent with --rows-json, a JSON array of {\"time\",\"label\"}."
    )
    @OptionGroup var global: GlobalOptions
    @Option(name: .long, help: "Heading.") var title: String
    @Option(name: .long, help: "Repeat for each row: time|label.") var row: [String] = []
    @Option(name: .customLong("rows-json"), help: "JSON array of time/label objects.") var rowsJSON: String?
    @Flag(name: .customLong("no-present"), help: "Do not bring the window forward.") var noPresent = false

    func run() async throws {
        var rows = try row.map(parseScheduleRow)
        if let rowsJSON {
            rows.append(contentsOf: try JSONDecoder().decode([ScheduleRow].self, from: Data(rowsJSON.utf8)))
        }
        guard !rows.isEmpty else { throw HomeSignalError.usage("Provide at least one --row or --rows-json. Refusing to replace the screen.") }
        let config = try CLIRuntime.load(global)
        let doc = document(from: config, kind: DisplayKind.schedule, title: title, message: nil, rows: rows)
        _ = try DisplayRendering.prepare(doc)
        let params = DisplayShowParams(document: doc, present: !noPresent)
        try await IPCCall.perform(global: global, command: "display.schedule", method: IPCMethod.displayShow, params: try params.jsonValue())
    }
}

struct DisplayLayoutCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "layout",
        abstract: "Render a JSON module spec onto the 16:9 canvas and show it.",
        discussion: """
        Pass --file or --spec, not both. The spec is a JSON object with title, an optional theme \
        (default or moonlit-autumn), and a non-empty modules array. Module types are header, message, \
        columns, list, summary, and alert. Blocks share a grid with gap equal to the l space token and \
        flex to fill the canvas. Text uses the type scale and steps down when it would overflow. \
        An empty file, empty spec, unknown theme, unknown module, or blank module text is an error and \
        does not replace the page. The rendered HTML is shown as-is and read back like display html. \
        The result includes contentHash, title, verified, and html. The same spec renders the same page. \
        display html still shows caller HTML unchanged.
        """
    )
    @OptionGroup var global: GlobalOptions
    @Option(name: .long, help: "UTF-8 JSON spec file.") var file: String?
    @Option(name: .long, help: "JSON spec. Use --file for a longer document.") var spec: String?
    @Option(name: .long, help: "Theme id. Overrides the spec. Built-in themes: default, moonlit-autumn.") var theme: String?
    @Flag(name: .customLong("no-present"), help: "Do not bring the window forward.") var noPresent = false

    func run() async throws {
        let json = try loadJSON()
        let markup = try DisplayLayout.render(json: json, theme: theme)
        let config = try CLIRuntime.load(global)
        let doc = document(from: config, kind: DisplayKind.layout, title: nil, message: nil, rows: [], html: markup)
        _ = try DisplayRendering.prepare(doc)
        let result = try await IPCCall.send(
            global: global,
            method: IPCMethod.displayShow,
            params: try DisplayShowParams(document: doc, present: !noPresent).jsonValue()
        )
        var fields = result.object ?? [:]
        fields["html"] = .string(markup)
        CLIRuntime.succeed(command: "display.layout", global: global, value: .object(fields))
    }

    private func loadJSON() throws -> String {
        if file != nil && spec != nil {
            throw HomeSignalError.usage("Pass only one of --file or --spec.")
        }
        if let spec {
            guard !spec.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw HomeSignalError.displayRefusal("Layout spec is empty.")
            }
            return spec
        }
        if let file {
            let path = HomeSignalPaths.expand(file)
            guard FileManager.default.fileExists(atPath: path) else {
                throw HomeSignalError.displayRefusal("Layout file not found: \(path).")
            }
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            guard let text = String(data: data, encoding: .utf8) else {
                throw HomeSignalError.displayRefusal("Layout file must be UTF-8: \(path).")
            }
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw HomeSignalError.displayRefusal("Layout file is empty.")
            }
            return text
        }
        throw HomeSignalError.displayRefusal("display layout needs --file or --spec.")
    }
}

struct DisplayHTML: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "html",
        abstract: "Show an HTML file or string exactly, without wrapping it in the message template.",
        discussion: "Pass --file or --html, not both. The bytes are loaded as provided. An empty file or string is an error and does not replace the page. The result contentHash is the SHA-256 of those bytes, and title is the document title element when it has one."
    )
    @OptionGroup var global: GlobalOptions
    @Option(name: .long, help: "UTF-8 HTML file to show.") var file: String?
    @Option(name: .long, help: "HTML document to show.") var html: String?
    @Flag(name: .customLong("no-present"), help: "Do not bring the window forward.") var noPresent = false

    func run() async throws {
        if file != nil && html != nil {
            throw HomeSignalError.usage("Pass only one of --file or --html.")
        }
        let markup: String
        if let file {
            let path = HomeSignalPaths.expand(file)
            guard FileManager.default.fileExists(atPath: path) else {
                throw HomeSignalError.usage("HTML file not found: \(path)")
            }
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            guard let text = String(data: data, encoding: .utf8) else {
                throw HomeSignalError.usage("HTML file must be UTF-8: \(path)")
            }
            markup = text
        } else if let html {
            markup = html
        } else {
            throw HomeSignalError.usage("display html needs --file or --html. Refusing to replace custom content.")
        }
        let config = try CLIRuntime.load(global)
        let doc = document(from: config, kind: DisplayKind.html, title: nil, message: nil, rows: [], html: markup)
        _ = try DisplayRendering.prepare(doc)
        let params = DisplayShowParams(document: doc, present: !noPresent)
        try await IPCCall.perform(global: global, command: "display.html", method: IPCMethod.displayShow, params: try params.jsonValue())
    }
}

struct DisplayClear: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "clear", abstract: "Replace the window contents with an empty page.")
    @OptionGroup var global: GlobalOptions
    @Flag(name: .customLong("no-present"), help: "Do not bring the window forward.") var noPresent = false
    func run() async throws {
        try await IPCCall.perform(
            global: global,
            command: "display.clear",
            method: IPCMethod.displayClear,
            params: try PresentParams(present: !noPresent).jsonValue()
        )
    }
}

struct DisplayStatus: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "status", abstract: "Print the document currently shown, or null.")
    @OptionGroup var global: GlobalOptions
    func run() async throws {
        try await IPCCall.perform(global: global, command: "display.status", method: IPCMethod.displayStatus)
    }
}

struct MirrorCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mirror",
        abstract: "Connect, disconnect, or inspect an AirPlay target by name.",
        discussion: """
        The agent opens Control Center with System Events, because the route list is not a public headless API. \
        Window mode then clicks Choose Content, Window or App, and Mirror This Window using fractions of the panel frame \
        from config. Connecting when the target is already connected does nothing. \
        --dry-run still opens Control Center to read the checkbox, and does not click the target.
        """,
        subcommands: [MirrorStatusCommand.self, MirrorConnectCommand.self, MirrorDisconnectCommand.self]
    )
}

struct MirrorStatusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "status", abstract: "Read whether the target is selected.")
    @OptionGroup var global: GlobalOptions
    @Option(name: .long, help: "AirPlay name. Defaults to mirror.target in config.") var target: String?
    func run() async throws {
        let name = try target ?? CLIRuntime.load(global).mirror.target
        try await IPCCall.perform(global: global, command: "mirror.status", method: IPCMethod.mirrorStatus, params: try MirrorTargetParams(target: name).jsonValue())
    }
}

struct MirrorConnectCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "connect",
        abstract: "Mirror this Mac, or the agent window, to an AirPlay target.",
        discussion: "mode is window (the signal window) or display (the whole screen). Already-connected targets return changed: false."
    )
    @OptionGroup var global: GlobalOptions
    @Option(name: .long, help: "AirPlay name. Defaults to config.") var target: String?
    @Option(name: .long, help: "window or display. Defaults to config.") var mode: String?
    func run() async throws {
        let config = try CLIRuntime.load(global)
        let params = MirrorConnectParams(target: target ?? config.mirror.target, mode: mode ?? config.mirror.mode)
        try await IPCCall.perform(global: global, command: "mirror.connect", method: IPCMethod.mirrorConnect, params: try params.jsonValue())
    }
}

struct MirrorDisconnectCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "disconnect",
        abstract: "Stop mirroring to the target.",
        discussion: "Disconnecting when the target is already off returns changed: false."
    )
    @OptionGroup var global: GlobalOptions
    @Option(name: .long, help: "AirPlay name. Defaults to config.") var target: String?
    func run() async throws {
        let name = try target ?? CLIRuntime.load(global).mirror.target
        try await IPCCall.perform(global: global, command: "mirror.disconnect", method: IPCMethod.mirrorDisconnect, params: try MirrorTargetParams(target: name).jsonValue())
    }
}

struct InputCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "input",
        abstract: "Move, click, scroll, or park the pointer.",
        discussion: "Coordinates are global points, origin at the top left of the primary display, y downward. --dry-run prints the point and does not post events.",
        subcommands: [InputClick.self, InputMove.self, InputScroll.self, InputPark.self]
    )
}

struct InputClick: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "click", abstract: "Click at a point. --clicks 2 is a double-click.")
    @OptionGroup var global: GlobalOptions
    @Argument var x: Double
    @Argument var y: Double
    @Option(name: .long, help: "left or right.") var button: String = "left"
    @Option(name: .long, help: "Click count, from 1 to 3.") var clicks: Int = 1
    func run() async throws {
        let params = InputClickParams(x: x, y: y, button: button, clicks: clicks)
        try await IPCCall.perform(global: global, command: "input.click", method: IPCMethod.inputClick, params: try params.jsonValue())
    }
}

struct InputMove: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "move", abstract: "Move the pointer.")
    @OptionGroup var global: GlobalOptions
    @Argument var x: Double
    @Argument var y: Double
    func run() async throws {
        try await IPCCall.perform(global: global, command: "input.move", method: IPCMethod.inputMove, params: try InputMoveParams(x: x, y: y).jsonValue())
    }
}

struct InputScroll: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "scroll",
        abstract: "Scroll at a point.",
        discussion: "Positive --delta scrolls up or right. That is the CoreGraphics wheel sign."
    )
    @OptionGroup var global: GlobalOptions
    @Argument var x: Double
    @Argument var y: Double
    @Option(name: .long, help: "Wheel delta in lines.") var delta: Int
    @Option(name: .long, help: "vertical or horizontal.") var axis: String = "vertical"
    func run() async throws {
        let params = InputScrollParams(x: x, y: y, delta: delta, axis: axis)
        try await IPCCall.perform(global: global, command: "input.scroll", method: IPCMethod.inputScroll, params: try params.jsonValue())
    }
}

struct InputPark: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "park",
        abstract: "Move the pointer to a corner of a named display.",
        discussion: "The point is computed from the display origin, size, corner, and inset. Defaults come from config."
    )
    @OptionGroup var global: GlobalOptions
    @Option(name: .long, help: "Display name from `displays`.") var display: String?
    @Option(name: .long, help: "bottom-right, bottom-left, top-right, or top-left.") var corner: String?
    @Option(name: .long, help: "Inset from the corner, in points.") var inset: Int?
    func run() async throws {
        let config = try CLIRuntime.load(global)
        let params = InputParkParams(
            display: display ?? config.input.parkDisplay,
            corner: corner ?? config.input.parkCorner,
            inset: inset ?? config.input.parkInset
        )
        try await IPCCall.perform(global: global, command: "input.park", method: IPCMethod.inputPark, params: try params.jsonValue())
    }
}

struct ScreenshotCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "screenshot",
        abstract: "Capture one display to a PNG file.",
        discussion: "Requires Screen Recording permission. --dry-run prints the path it would write and does not capture. --display is a name from `displays`."
    )
    @OptionGroup var global: GlobalOptions
    @Option(name: .long, help: "Display name. Defaults to the signal display in config.") var display: String?
    @Option(name: .long, help: "Output path.") var out: String?

    func run() async throws {
        let config = try CLIRuntime.load(global)
        let params = ScreenshotParams(display: display ?? config.display.displayName, path: out)
        try await IPCCall.perform(global: global, command: "screenshot", method: IPCMethod.captureScreenshot, params: try params.jsonValue())
    }
}

enum CommandCatalog {
    static let commands: [CommandSpec] = [
        CommandSpec(name: "describe", summary: "Manifest of commands and exit codes.", mutating: false, idempotent: true, arguments: [], options: []),
        CommandSpec(name: "version", summary: "CLI and protocol version.", mutating: false, idempotent: true, arguments: [], options: []),
        CommandSpec(name: "config show", summary: "Effective configuration.", mutating: false, idempotent: true, arguments: [], options: []),
        CommandSpec(name: "config path", summary: "Config file path.", mutating: false, idempotent: true, arguments: [], options: []),
        CommandSpec(name: "config init", summary: "Write the example config if missing.", mutating: true, idempotent: true, arguments: [], options: []),
        CommandSpec(name: "daemon status", summary: "Ping the agent.", mutating: false, idempotent: true, arguments: [], options: []),
        CommandSpec(name: "daemon stop", summary: "Stop the agent.", mutating: true, idempotent: false, arguments: [], options: []),
        CommandSpec(name: "capabilities", summary: "Methods and backend reported by the agent.", mutating: false, idempotent: true, arguments: [], options: []),
        CommandSpec(name: "displays", summary: "Displays used for input, capture, and the signal window.", mutating: false, idempotent: true, arguments: [], options: []),
        CommandSpec(name: "device list", summary: "List lights.", mutating: false, idempotent: true, arguments: [], options: []),
        CommandSpec(name: "device get", summary: "Read a light.", mutating: false, idempotent: true, arguments: ["name"], options: []),
        CommandSpec(name: "device set", summary: "Set light fields.", mutating: true, idempotent: true, arguments: ["name"], options: ["on", "off", "brightness", "hue", "saturation", "color-temperature", "color"]),
        CommandSpec(name: "device blink", summary: "Blink a light and restore the prior state.", mutating: true, idempotent: false, arguments: ["name"], options: ["times", "color", "on-ms", "off-ms"]),
        CommandSpec(name: "scene list", summary: "List scenes.", mutating: false, idempotent: true, arguments: [], options: []),
        CommandSpec(name: "scene run", summary: "Run a scene.", mutating: true, idempotent: false, arguments: ["name"], options: []),
        CommandSpec(name: "display message", summary: "Show text on the signal window. Empty text is an error.", mutating: true, idempotent: true, arguments: ["text"], options: ["title", "no-present"]),
        CommandSpec(name: "display schedule", summary: "Show a title and time/label rows.", mutating: true, idempotent: true, arguments: [], options: ["title", "row", "rows-json", "no-present"]),
        CommandSpec(name: "display layout", summary: "Render a JSON module spec on the 16:9 canvas and verify the read-back. Empty or invalid specs are an error.", mutating: true, idempotent: true, arguments: [], options: ["file", "spec", "theme", "no-present"]),
        CommandSpec(name: "display html", summary: "Show caller HTML exactly and verify the read-back hash.", mutating: true, idempotent: true, arguments: [], options: ["file", "html", "no-present"]),
        CommandSpec(name: "display clear", summary: "Show an empty page.", mutating: true, idempotent: true, arguments: [], options: ["no-present"]),
        CommandSpec(name: "display status", summary: "Current signal document.", mutating: false, idempotent: true, arguments: [], options: []),
        CommandSpec(name: "mirror status", summary: "Whether an AirPlay target is selected.", mutating: false, idempotent: true, arguments: [], options: ["target"]),
        CommandSpec(name: "mirror connect", summary: "Mirror to an AirPlay target.", mutating: true, idempotent: true, arguments: [], options: ["target", "mode"]),
        CommandSpec(name: "mirror disconnect", summary: "Stop mirroring to a target.", mutating: true, idempotent: true, arguments: [], options: ["target"]),
        CommandSpec(name: "input click", summary: "Click.", mutating: true, idempotent: true, arguments: ["x", "y"], options: ["button", "clicks"]),
        CommandSpec(name: "input move", summary: "Move the pointer.", mutating: true, idempotent: true, arguments: ["x", "y"], options: []),
        CommandSpec(name: "input scroll", summary: "Scroll.", mutating: true, idempotent: false, arguments: ["x", "y"], options: ["delta", "axis"]),
        CommandSpec(name: "input park", summary: "Park the pointer in a display corner.", mutating: true, idempotent: true, arguments: [], options: ["display", "corner", "inset"]),
        CommandSpec(name: "screenshot", summary: "Capture a display.", mutating: true, idempotent: false, arguments: [], options: ["display", "out"]),
    ]

    static var manifest: CommandManifest {
        CommandManifest(
            name: "home-signal",
            version: HomeSignalVersion.current,
            protocolVersion: HomeSignalVersion.protocolVersion,
            configPath: "~/.config/home-signal/config.toml",
            socketPath: "~/.local/share/home-signal/agent.sock",
            globalOptions: ["json", "dry-run", "config", "socket"],
            exitCodes: [
                ExitCodeSpec(code: 0, name: "ok", meaning: "Success."),
                ExitCodeSpec(code: 1, name: "usage", meaning: "The command line or parameters were invalid."),
                ExitCodeSpec(code: 2, name: "config", meaning: "The config file was missing or invalid."),
                ExitCodeSpec(code: 3, name: "not_found", meaning: "A light, scene, display, or AirPlay target was not found."),
                ExitCodeSpec(code: 4, name: "backend", meaning: "The device backend or a system tool failed."),
                ExitCodeSpec(code: 5, name: "daemon_unavailable", meaning: "HomeSignalAgent is not listening on the socket."),
                ExitCodeSpec(code: 6, name: "unsupported", meaning: "This build cannot do that, or a permission is missing."),
                ExitCodeSpec(code: 7, name: "timeout", meaning: "The operation timed out."),
                ExitCodeSpec(code: 8, name: "restore_failed", meaning: "A blink did not restore the prior light state."),
                ExitCodeSpec(code: 64, name: "cli_usage", meaning: "ArgumentParser rejected the command line."),
            ],
            commands: commands
        )
    }
}

struct CommandSpec: Encodable, Sendable {
    var name: String
    var summary: String
    var mutating: Bool
    var idempotent: Bool
    var arguments: [String]
    var options: [String]
}

struct ExitCodeSpec: Encodable, Sendable {
    var code: Int
    var name: String
    var meaning: String
}

struct CommandManifest: Encodable, Sendable {
    var name: String
    var version: String
    var protocolVersion: Int
    var configPath: String
    var socketPath: String
    var globalOptions: [String]
    var exitCodes: [ExitCodeSpec]
    var commands: [CommandSpec]
}

public enum CLI {
    public static func run(_ arguments: [String], hooks: CLIHooks = CLIHooks()) async -> Int32 {
        await CLIRuntime.$hooks.withValue(hooks) {
            await runBody(arguments)
        }
    }

    private static func runBody(_ arguments: [String]) async -> Int32 {
        let json = CLIArgv.wantsJSON(arguments)
        do {
            var command = try Root.parseAsRoot(CLIArgv.normalize(arguments))
            if var asyncCommand = command as? any AsyncParsableCommand {
                try await asyncCommand.run()
            } else {
                try command.run()
            }
            return 0
        } catch let error as HomeSignalError {
            CLIRuntime.fail(command: "", dryRun: arguments.contains("--dry-run"), json: json, error: error)
            return error.exitCode
        } catch {
            let code = Root.exitCode(for: error)
            let text = Root.fullMessage(for: error, columns: 100)
            let sink = CLIRuntime.hooks.sink
            if !text.isEmpty {
                let rendered = text.hasSuffix("\n") ? text : text + "\n"
                if code.isSuccess {
                    sink.writeOut(rendered)
                } else if json {
                    CLIRuntime.fail(command: "", dryRun: false, json: true, error: .usage(text.trimmingCharacters(in: .whitespacesAndNewlines)))
                } else {
                    sink.writeErr(rendered)
                }
            }
            return code.rawValue
        }
    }
}
