import XCTest
@testable import HomeSignalCore
@testable import HomeSignalMirroring

final class RouteSelectionTests: XCTestCase {
    func testLockedSessionReadsEitherFlag() {
        XCTAssertTrue(SessionLockText.isLocked(session: ["CGSSessionScreenIsLocked": "Yes"], consoleLocked: nil))
        XCTAssertTrue(SessionLockText.isLocked(session: [:], consoleLocked: "1"))
        XCTAssertTrue(SessionLockText.isLocked(session: ["IOConsoleLocked": "true"], consoleLocked: "no"))
        XCTAssertFalse(SessionLockText.isLocked(session: ["CGSSessionScreenIsLocked": "No"], consoleLocked: "false"))
    }

    func testChooseKeepsVideoRoutesAndDropsLocalAudioWhenFeaturesAreKnown() {
        let snapshot = sample(
            devices: [
                candidate("Mac", video: true, local: true),
                candidate("Example Speaker", video: false, screen: false),
                candidate("Example TV", identifier: "example-1", video: true),
            ],
            screen: false,
            known: true
        )
        XCTAssertEqual(RouteSelection.choose(snapshot).map(\.name), ["Example TV"])
        XCTAssertEqual(RouteSelection.match(target: "example tv", deviceID: "", in: RouteSelection.choose(snapshot))?.identifier, "example-1")
    }

    func testUnknownFeaturesListEveryNonLocalDevice() {
        let snapshot = sample(
            devices: [
                candidate("Example Speaker", video: false, screen: false),
                candidate("Mac", local: true),
            ],
            screen: false,
            known: false
        )
        XCTAssertEqual(RouteSelection.choose(snapshot).map(\.name), ["Example Speaker"])
    }

    func testObjectReturnEncodingSkipsNonObjects() {
        XCTAssertTrue(ObjCReturn.returnsObject("@16@0:8"))
        XCTAssertTrue(ObjCReturn.returnsObject("@@:"))
        XCTAssertTrue(ObjCReturn.returnsObject("r@16@0:8"))
        XCTAssertFalse(ObjCReturn.returnsObject("v16@0:8"))
        XCTAssertFalse(ObjCReturn.returnsObject("#16@0:8"))
        XCTAssertFalse(ObjCReturn.returnsObject("^{__CFString=}16@0:8"))
        XCTAssertFalse(ObjCReturn.returnsObject(""))
        XCTAssertTrue(ObjCReturn.returnsVoid("v16@0:8"))
        XCTAssertTrue(ObjCReturn.returnsBool("B16@0:8"))
        XCTAssertTrue(ObjCReturn.returnsBool("c16@0:8"))
    }

    func testProbeCrashBecomesAnErrorInsteadOfKillingTheAgent() throws {
        let report = ProbeOutput.interpret(status: 11, signaled: true, stdout: Data(), stderr: "")
        XCTAssertTrue(report.snapshot.note.contains("signal 11"))
        XCTAssertTrue(report.snapshot.note.contains("agent stayed up"))
        XCTAssertEqual(report.error, report.snapshot.note)
        XCTAssertFalse(report.snapshot.loaded)
        let ok = ProbeReport(
            snapshot: RouteSnapshot(
                classes: ["AVOutputContext": true],
                selectors: ["AVOutputContext.sharedSystemScreenContext": true],
                devices: [],
                screenContext: false,
                featuresKnown: false,
                note: "No screen-mirroring context was found.",
                encodings: ["AVOutputContext.sharedSystemScreenContext": "@16@0:8"],
                called: ["AVOutputContext.sharedSystemScreenContext": false]
            ),
            error: nil
        )
        let data = try JSONEncoder().encode(ok)
        let decoded = ProbeOutput.interpret(status: 0, signaled: false, stdout: data, stderr: "")
        XCTAssertEqual(decoded.snapshot.classes["AVOutputContext"], true)
        XCTAssertEqual(decoded.snapshot.encodings["AVOutputContext.sharedSystemScreenContext"], "@16@0:8")
        let text = RouteSelection.debugText(decoded.snapshot)
        XCTAssertTrue(text.contains("encoding=@16@0:8"))
        XCTAssertTrue(text.contains("called=no"))
        let traced = RouteSelection.debugText(RouteSnapshot(
            classes: [:],
            selectors: [:],
            devices: [],
            screenContext: false,
            featuresKnown: false,
            note: "",
            trace: ["screenReturn AVOutputContext.sharedSystemScreenContext=nil", "method AVOutputContext +sharedSystemScreenContext encoding=@16@0:8"]
        ))
        XCTAssertTrue(traced.contains("screenReturn AVOutputContext.sharedSystemScreenContext=nil"))
        XCTAssertTrue(traced.contains("method AVOutputContext +sharedSystemScreenContext encoding=@16@0:8"))
    }

    func testDebugTextListsClassesSelectorsAndDevices() {
        let text = RouteSelection.debugText(sample(devices: [candidate("Example TV", identifier: "example-1", screen: true)], screen: false, known: true))
        XCTAssertTrue(text.contains("class AVOutputContext=yes"))
        XCTAssertTrue(text.contains("class MRAVOutputContext=no"))
        XCTAssertTrue(text.contains("selector MRAVOutputContext.sharedSystemScreenMirroringContext=no"))
        XCTAssertTrue(text.contains("device name=Example TV id=example-1"))
        XCTAssertTrue(text.contains("screenContext=no"))
        XCTAssertTrue(text.contains("note="))
    }

    func testRoutingListDebugAndLockedControlCenter() async throws {
        let probe = FixedProbe(sample(devices: [candidate("Example TV", identifier: "example-1", video: true)], screen: true, known: true))
        let interface = RecordingMirror()
        let mirror = AdaptiveMirror(routing: MediaRoutingMirror(probe: probe), interface: interface, locks: LockedSession())
        let listed = try await mirror.list(backend: "routing", discover: false, debugAX: false, debugFile: nil, routingDebug: true)
        XCTAssertEqual(listed.source, "routing")
        XCTAssertEqual(listed.controlCenter, ["Example TV"])
        XCTAssertTrue(listed.routingDebug?.contains("selector MRAVOutputContext.sharedSystemScreenMirroringContext=yes") == true)
        do {
            _ = try await mirror.list(backend: "controlcenter", discover: false, debugAX: false, debugFile: nil, routingDebug: false)
            XCTFail("expected a locked screen")
        } catch let error as HomeSignalError {
            XCTAssertEqual(error.code, "screen_locked")
            XCTAssertEqual(error.exitCode, 6)
        }
        let calls = await interface.lists
        XCTAssertEqual(calls, 0)
    }

    func testAutoUsesRoutingNamesAndFallsBackOnlyWhenTheScreenIsUnlocked() async throws {
        let video = AdaptiveMirror(
            routing: MediaRoutingMirror(probe: FixedProbe(sample(devices: [candidate("Example TV", video: true)], screen: false, known: true))),
            interface: RecordingMirror(),
            locks: UnlockedSession()
        )
        let listed = try await video.list(backend: "auto", discover: false, debugAX: false, debugFile: nil, routingDebug: false)
        XCTAssertEqual(listed.controlCenter, ["Example TV"])
        XCTAssertEqual(listed.source, "routing")

        let interface = RecordingMirror()
        let empty = AdaptiveMirror(
            routing: MediaRoutingMirror(probe: FixedProbe(sample(devices: [candidate("Example Speaker")], screen: false, known: true))),
            interface: interface,
            locks: UnlockedSession()
        )
        let fallback = try await empty.list(backend: "auto", discover: false, debugAX: false, debugFile: nil, routingDebug: false)
        let uiLists = await interface.lists
        XCTAssertEqual(fallback.controlCenter, ["From UI"])
        XCTAssertEqual(uiLists, 1)

        let locked = AdaptiveMirror(
            routing: MediaRoutingMirror(probe: FixedProbe(sample(devices: [candidate("Example Speaker")], screen: false, known: true))),
            interface: RecordingMirror(),
            locks: LockedSession()
        )
        let held = try await locked.list(backend: "auto", discover: false, debugAX: false, debugFile: nil, routingDebug: false)
        XCTAssertEqual(held.controlCenter, [])
        XCTAssertEqual(held.source, "routing")
    }

    func testConnectWithoutAScreenContextDoesNotPretendToMirror() async throws {
        let probe = FixedProbe(sample(devices: [candidate("Example TV", identifier: "example-1", video: true)], screen: false, known: true))
        let interface = RecordingMirror()
        let locked = AdaptiveMirror(routing: MediaRoutingMirror(probe: probe), interface: interface, locks: LockedSession())
        do {
            _ = try await locked.connect(backend: "auto", target: "Example TV", mode: "display", deviceID: "", dryRun: false, debugAX: false, debugFile: nil, routingDebug: true)
            XCTFail("expected the locked screen")
        } catch let error as HomeSignalError {
            XCTAssertEqual(error.code, "screen_locked")
            XCTAssertTrue(error.hint?.contains("screen-mirroring") == true || error.hint?.contains("screen_mirror") == true || (error.hint?.contains("Media routing") == true))
        }
        let lockedConnects = await interface.connects
        XCTAssertEqual(probe.sets, [])
        XCTAssertEqual(lockedConnects, 0)

        let unlockedInterface = RecordingMirror()
        let unlocked = AdaptiveMirror(routing: MediaRoutingMirror(probe: probe), interface: unlockedInterface, locks: UnlockedSession())
        let status = try await unlocked.connect(backend: "auto", target: "Example TV", mode: "display", deviceID: "", dryRun: false, debugAX: false, debugFile: nil, routingDebug: false)
        let uiConnects = await unlockedInterface.connects
        XCTAssertEqual(status.mode, "display")
        XCTAssertEqual(uiConnects, 1)
        XCTAssertEqual(probe.sets, [])
    }

    func testScreenContextConnectsByIdentifier() async throws {
        let probe = FixedProbe(sample(devices: [candidate("Example TV", identifier: "example-1", screen: true)], screen: true, known: true))
        let interface = RecordingMirror()
        let mirror = AdaptiveMirror(routing: MediaRoutingMirror(probe: probe), interface: interface, locks: LockedSession())
        let status = try await mirror.connect(backend: "routing", target: "Example TV", mode: "display", deviceID: "", dryRun: false, debugAX: false, debugFile: nil, routingDebug: true)
        XCTAssertTrue(status.connected)
        XCTAssertTrue(status.changed)
        let uiConnects = await interface.connects
        XCTAssertEqual(probe.sets, ["example-1"])
        XCTAssertEqual(uiConnects, 0)
        XCTAssertTrue(status.note?.contains("screenContext=yes") == true)
    }

    func testBackendNameIsRejectedWhenUnknown() async throws {
        let mirror = AdaptiveMirror(
            routing: MediaRoutingMirror(probe: FixedProbe(sample(devices: [], screen: false, known: false))),
            interface: RecordingMirror(),
            locks: UnlockedSession()
        )
        do {
            _ = try await mirror.list(backend: "bluetooth", discover: false, debugAX: false, debugFile: nil, routingDebug: false)
            XCTFail("expected usage")
        } catch let error as HomeSignalError {
            XCTAssertEqual(error.code, "usage")
            XCTAssertEqual(error.exitCode, 1)
        } catch {
            XCTFail("unexpected error")
        }
    }
}

private func candidate(_ name: String, identifier: String = "", video: Bool = false, screen: Bool = false, local: Bool = false) -> RouteCandidate {
    RouteCandidate(name: name, identifier: identifier, video: video, screen: screen, selected: false, local: local)
}

private func sample(devices: [RouteCandidate], screen: Bool, known: Bool, loaded: Bool = true) -> RouteSnapshot {
    RouteSnapshot(
        classes: ["AVOutputContext": loaded, "MRAVOutputContext": false],
        selectors: ["MRAVOutputContext.sharedSystemScreenMirroringContext": screen],
        devices: devices,
        screenContext: screen,
        featuresKnown: known,
        note: screen ? "A screen-mirroring context was found." : "No screen-mirroring context was found. Shared audio and video output contexts do not mirror the display."
    )
}

private final class FixedProbe: MediaRouteProbing, @unchecked Sendable {
    var snap: RouteSnapshot
    var sets: [String] = []

    init(_ snap: RouteSnapshot) {
        self.snap = snap
    }

    func snapshot() async -> RouteSnapshot { snap }

    func setScreenRoute(identifier: String, enabled: Bool, dryRun: Bool) async throws -> RouteSnapshot {
        _ = (enabled, dryRun)
        sets.append(identifier)
        return snap
    }
}

private actor RecordingMirror: MirrorChannel {
    var lists = 0
    var connects = 0

    func status(target: String, debugAX: Bool, debugFile: String?) async throws -> MirrorStatus {
        _ = (debugAX, debugFile)
        return MirrorStatus(target: target, connected: false, mode: nil, changed: false)
    }

    func connect(target: String, mode: String, deviceID: String, dryRun: Bool, debugAX: Bool, debugFile: String?) async throws -> MirrorStatus {
        _ = (deviceID, dryRun, debugAX, debugFile)
        connects += 1
        return MirrorStatus(target: target, connected: true, mode: mode, changed: true)
    }

    func disconnect(target: String, dryRun: Bool, debugAX: Bool, debugFile: String?) async throws -> MirrorStatus {
        _ = (dryRun, debugAX, debugFile)
        return MirrorStatus(target: target, connected: false, changed: false)
    }

    func list(discover: Bool, debugAX: Bool, debugFile: String?) async throws -> MirrorListResult {
        _ = (discover, debugAX, debugFile)
        lists += 1
        return MirrorListResult(
            controlCenter: ["From UI"],
            discovered: [],
            routes: [MirrorRoute(name: "From UI", identifier: "", selected: false)],
            accessibility: [],
            source: "controlcenter"
        )
    }
}
