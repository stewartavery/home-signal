import HomeSignalCore

public struct DisplaySession: Sendable {
    public var power: any DisplayPowerControlling
    public var screens: any AttachedDisplayListing
    public var mirror: any MirrorChannel
    public var placer: any DisplayPlacing
    public var sleeper: any Sleeper
    public var reconnectSeconds: Double
    public var pollMilliseconds: Int
    public var mirrorMode: String

    public init(
        power: any DisplayPowerControlling,
        screens: any AttachedDisplayListing,
        mirror: any MirrorChannel,
        placer: any DisplayPlacing,
        sleeper: any Sleeper,
        reconnectSeconds: Double,
        pollMilliseconds: Int = 200,
        mirrorMode: String
    ) {
        self.power = power
        self.screens = screens
        self.mirror = mirror
        self.placer = placer
        self.sleeper = sleeper
        self.reconnectSeconds = reconnectSeconds
        self.pollMilliseconds = pollMilliseconds
        self.mirrorMode = mirrorMode
    }

    public func show(
        html: String,
        readback: DisplayReadback,
        present: Bool,
        target: DisplayTarget,
        alreadyHolding: Bool
    ) async throws -> DisplayShowResult {
        let mode = try MirrorMode.validate(mirrorMode)
        var placed = false
        do {
            try await wake()
            let found = try await ensureAttached(target, mode: mode)
            placed = true
            let report = try await placer.place(html: html, kind: readback.kind, present: present, target: foundTarget(found))
            try confirm(report, matches: found, expected: readback)
            let attached = await screens.attachedDisplays()
            return DisplayShowResult(
                contentHash: report.readback.contentHash,
                title: report.readback.title,
                kind: report.readback.kind,
                verified: true,
                target: target.name,
                deviceID: target.deviceID,
                screen: found.name,
                fullScreen: true,
                onTarget: true,
                holdingWake: true,
                dryRun: false,
                attached: attached.map(\.name)
            )
        } catch {
            if placed {
                await placer.dismiss()
                await power.release()
            } else if !alreadyHolding {
                await power.release()
            }
            throw error
        }
    }

    public func stop() async {
        await placer.dismiss()
        await power.release()
    }

    private func wake() async throws {
        do {
            try await power.wakeAndHold(reason: "home-signal display")
        } catch let error as HomeSignalError {
            if error.step == nil {
                throw HomeSignalError.displayStep("wake", error.message, exitCode: error.exitCode)
            }
            throw error
        } catch {
            throw HomeSignalError.displayStep("wake", String(describing: error))
        }
    }

    private func ensureAttached(_ target: DisplayTarget, mode: String) async throws -> AttachedDisplay {
        if let found = DisplayMatch.find(target, in: await screens.attachedDisplays()) {
            return found
        }
        do {
            _ = try await mirror.connect(target: target.name, mode: mode, deviceID: target.deviceID, dryRun: false, debugAX: false)
        } catch let error as HomeSignalError {
            throw HomeSignalError.displayStep("reconnect", error.message, exitCode: error.exitCode)
        } catch {
            throw HomeSignalError.displayStep("reconnect", String(describing: error))
        }
        return try await waitForTarget(target)
    }

    private func waitForTarget(_ target: DisplayTarget) async throws -> AttachedDisplay {
        let timeoutMs = max(0, Int((reconnectSeconds * 1000).rounded()))
        let poll = max(1, pollMilliseconds)
        var waited = 0
        while true {
            let attached = await screens.attachedDisplays()
            if let found = DisplayMatch.find(target, in: attached) {
                return found
            }
            if waited >= timeoutMs {
                throw HomeSignalError.displayStep(
                    "reconnect",
                    "Target display \(label(target)) is not attached. Reconnect did not add it within \(reconnectSeconds) seconds. Attached: \(list(attached)).",
                    exitCode: 7
                )
            }
            let step = min(poll, max(0, timeoutMs - waited))
            if step == 0 {
                waited = timeoutMs
                continue
            }
            try await sleeper.sleep(milliseconds: step)
            waited += step
        }
    }

    private func confirm(_ report: PlacementReport, matches found: AttachedDisplay, expected: DisplayReadback) throws {
        guard report.readback == expected else {
            throw HomeSignalError.displayMismatch(expected: expected, actual: report.readback)
        }
        let nameMatches = report.screenName == found.name
        let idMatches = found.deviceID.isEmpty || report.deviceID.isEmpty || report.deviceID == found.deviceID
        guard nameMatches && idMatches else {
            throw HomeSignalError.displayStep(
                "verify",
                "The window is on \(report.screenName), not \(found.name). Refusing to use another screen."
            )
        }
        guard report.fullScreen else {
            throw HomeSignalError.displayStep("verify", "The window on \(found.name) is not full screen.")
        }
    }

    private func foundTarget(_ screen: AttachedDisplay) -> DisplayTarget {
        DisplayTarget(name: screen.name, deviceID: screen.deviceID)
    }

    private func label(_ target: DisplayTarget) -> String {
        if target.deviceID.isEmpty { return target.name }
        return "\(target.name) (device \(target.deviceID))"
    }

    private func list(_ screens: [AttachedDisplay]) -> String {
        let names = screens.map(\.name)
        return names.isEmpty ? "none" : names.joined(separator: ", ")
    }
}

public struct ChannelDisplayPlacer: DisplayPlacing {
    private let channel: any DisplayChannel

    public init(_ channel: any DisplayChannel) {
        self.channel = channel
    }

    public func place(html: String, kind: String, present: Bool, target: DisplayTarget) async throws -> PlacementReport {
        let readback = try await channel.show(html: html, kind: kind, present: present)
        return PlacementReport(readback: readback, screenName: target.name, deviceID: target.deviceID, fullScreen: true)
    }

    public func dismiss() async {
        try? await channel.clear(present: true)
    }
}
