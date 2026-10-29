#if os(macOS)
import HomeSignalCore
import IOKit.pwr_mgt

public final class IOKitDisplayPower: DisplayPowerControlling, @unchecked Sendable {
    private let lock = NSLock()
    private var assertion: IOPMAssertionID = 0
    private var held = false

    public init() {}

    public func wakeAndHold(reason: String) async throws {
        lock.lock()
        defer { lock.unlock() }
        if held { return }
        // DeclareUserActivity wakes a sleeping display. The assertion keeps it awake until release.
        var activity = IOPMAssertionID(0)
        let activityResult = IOPMAssertionDeclareUserActivity(
            reason as CFString,
            kIOPMUserActiveLocal,
            &activity
        )
        guard activityResult == kIOReturnSuccess else {
            throw HomeSignalError.displayStep("wake", "Could not wake the display (IOReturn \(activityResult)).")
        }
        var created = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &created
        )
        guard result == kIOReturnSuccess else {
            throw HomeSignalError.displayStep("wake", "Could not hold a display-wake assertion (IOReturn \(result)).")
        }
        assertion = created
        held = true
    }

    public func release() async {
        lock.lock()
        defer { lock.unlock() }
        guard held else { return }
        _ = IOPMAssertionRelease(assertion)
        held = false
        assertion = 0
    }

    public func isHolding() async -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return held
    }

    deinit {
        if held {
            _ = IOPMAssertionRelease(assertion)
        }
    }
}
#endif
