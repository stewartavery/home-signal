#if os(macOS)
import Foundation
import HomeSignalCore
import IOKit.pwr_mgt

public final class IOKitDisplayPower: DisplayPowerControlling, @unchecked Sendable {
    private let lock = NSLock()
    private var assertion: IOPMAssertionID = 0
    private var held = false

    public init() {}

    public func wakeAndHold(reason: String) async throws {
        let failure: HomeSignalError? = try locked {
            if held { return nil }
            // DeclareUserActivity wakes a sleeping display. The assertion keeps it awake until release.
            var activity = IOPMAssertionID(0)
            let activityResult = IOPMAssertionDeclareUserActivity(
                reason as CFString,
                kIOPMUserActiveLocal,
                &activity
            )
            guard activityResult == kIOReturnSuccess else {
                return HomeSignalError.displayStep("wake", "Could not wake the display (IOReturn \(activityResult)).")
            }
            var created = IOPMAssertionID(0)
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                reason as CFString,
                &created
            )
            guard result == kIOReturnSuccess else {
                return HomeSignalError.displayStep("wake", "Could not hold a display-wake assertion (IOReturn \(result)).")
            }
            assertion = created
            held = true
            return nil
        }
        if let failure {
            throw failure
        }
    }

    public func release() async {
        locked {
            guard held else { return }
            _ = IOPMAssertionRelease(assertion)
            held = false
            assertion = 0
        }
    }

    public func isHolding() async -> Bool {
        locked { held }
    }

    deinit {
        if held {
            _ = IOPMAssertionRelease(assertion)
        }
    }

    private func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}
#endif
