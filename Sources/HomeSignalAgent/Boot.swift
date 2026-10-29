import ArgumentParser
import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif
import HomeSignalCapture
import HomeSignalCore
import HomeSignalDisplay
import HomeSignalInput
import HomeSignalKit
import HomeSignalLights
import HomeSignalMirroring

struct AgentCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "HomeSignalAgent",
        abstract: "Background process for home-signal. Serves the Unix socket and owns device and signal I/O.",
        discussion: """
        Run one agent per Mac. The home-signal CLI sends it JSON requests. \
        --simulate uses in-memory lights, a stored signal page, and no system events, \
        so the same binary can be exercised without HomeKit or a display. \
        Without --simulate, HomeKit is used only when this build can import it. \
        Otherwise set homekit.backend to shortcuts or http.
        """
    )

    @Flag(name: .long, help: "Use in-memory devices and channels instead of HomeKit and system UI.")
    var simulate = false

    @Option(name: .long, help: "Config file.")
    var config: String?

    @Option(name: .long, help: "Unix socket path. Overrides the config file.")
    var socket: String?

    func run() async throws {
        let loaded = try ConfigLoader.load(explicitPath: config)
        let socketPath = HomeSignalPaths.expand(socket ?? loaded.agent.socketPath)
        let displays = probedDisplays(configured: loaded.displays, simulate: simulate)
        let lights = try makeLights(loaded, simulate: simulate)
        let display = makeDisplay(loaded, displays: displays, simulate: simulate)
        let input = makeInput(simulate: simulate)
        let mirror = makeMirror(loaded, displays: displays, input: input, simulate: simulate)
        let capture = makeCapture(simulate: simulate)
        let stop = StopFlag()
        let runtime = AgentRuntime(
            config: loaded,
            displays: displays,
            lights: lights,
            display: display,
            mirror: mirror,
            input: input,
            capture: capture,
            stop: stop
        )
        Log(category: "agent").info("backend \(lights.backendID) simulate \(simulate)")
        try await AgentServer.serve(runtime: runtime, stop: stop, path: socketPath)
    }
}

private func probedDisplays(configured: [DisplayBounds], simulate: Bool) -> [DisplayBounds] {
    #if os(macOS)
    if !simulate {
        let probed = MacDisplayProbe.read()
        if !probed.isEmpty {
            return DisplayGeometry.applyingNames(probed: probed, configured: configured)
        }
    }
    #endif
    return configured
}

private func makeLights(_ config: HomeSignalConfig, simulate: Bool) throws -> any LightBackend {
    if simulate || config.homekit.backend == "simulated" {
        return SimulatedLightBackend(config: config.simulated)
    }
    switch config.homekit.backend {
    case "shortcuts":
        return ShortcutsLightBackend(names: config.homekit.shortcuts)
    case "http":
        return try HTTPLightBackend(config: config.homekit.http)
    case "homekit":
        #if canImport(HomeKit)
        return HomeKitLightBackend()
        #else
        throw HomeSignalError.unsupported(
            "This build cannot link HomeKit.",
            hint: "Set homekit.backend to shortcuts or http, or build the agent as a Mac Catalyst app with the HomeKit entitlement. See README.md."
        )
        #endif
    default:
        throw HomeSignalError.config("Unknown backend \(config.homekit.backend).")
    }
}

private func makeDisplay(_ config: HomeSignalConfig, displays: [DisplayBounds], simulate: Bool) -> any DisplayChannel {
    #if os(macOS)
    if !simulate {
        let name = config.display.displayName
        let snapshot = displays
        return MacDisplayChannel(screenName: name, displays: { snapshot })
    }
    #endif
    return SimulatedDisplay()
}

private func makeInput(simulate: Bool) -> any InputChannel {
    #if os(macOS)
    if !simulate {
        return CGEventPointer()
    }
    #endif
    return SimulatedPointer()
}

private func makeMirror(_ config: HomeSignalConfig, displays: [DisplayBounds], input: any InputChannel, simulate: Bool) -> any MirrorChannel {
    if simulate {
        return SimulatedMirror()
    }
    #if os(macOS)
    let snapshot = displays
    let system = SystemEventsMirror(
        config: config.mirror,
        displays: { snapshot },
        clicker: { point in
            _ = try await input.click(at: point, button: "left", clicks: 1, dryRun: false)
        }
    )
    return FallbackMirror(primary: UnavailableNativeMirror(), fallback: system)
    #else
    return UnavailableNativeMirror()
    #endif
}

private func makeCapture(simulate: Bool) -> any CaptureChannel {
    #if os(macOS)
    if !simulate {
        return ScreenCaptureChannel()
    }
    #endif
    return SimulatedCapture()
}

#if os(macOS)
import AppKit

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installStatusItem()
        Task {
            do {
                var command = try AgentCommand.parse()
                try await command.run()
                NSApplication.shared.terminate(nil)
            } catch {
                let text = AgentCommand.fullMessage(for: error)
                if !text.isEmpty {
                    FileHandle.standardError.write(Data((text.hasSuffix("\n") ? text : text + "\n").utf8))
                }
                let code = AgentCommand.exitCode(for: error).rawValue
                Darwin.exit(code == 0 ? 0 : code)
            }
        }
    }

    private func installStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.title = "HS"
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "home-signal", action: nil, keyEquivalent: ""))
        let quit = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusItem?.menu = menu
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
#else
@main
struct LinuxAgentMain {
    static func main() async {
        do {
            var command = try AgentCommand.parse()
            try await command.run()
        } catch {
            let text = AgentCommand.fullMessage(for: error)
            if !text.isEmpty {
                FileHandle.standardError.write(Data((text.hasSuffix("\n") ? text : text + "\n").utf8))
            }
            let code = AgentCommand.exitCode(for: error).rawValue
            exit(code == 0 ? 0 : code)
        }
    }
}
#endif
