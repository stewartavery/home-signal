import Foundation

public enum HomeKitBackendGate {
    public static func refusal(moduleAvailable: Bool, entitlementPresent: Bool) -> HomeSignalError? {
        if moduleAvailable && entitlementPresent { return nil }
        let why = moduleAvailable
            ? "This process is not signed with com.apple.developer.homekit."
            : "This build does not link the HomeKit framework."
        return HomeSignalError.unsupported(
            "HomeKit backend is unavailable. \(why) Apple issues that entitlement for a signed Mac Catalyst or iOS app, not for this menu-bar agent or a command-line binary.",
            hint: "Set homekit.backend to \"shortcuts\" or \"http\". See README.md."
        )
    }

    public static func plistGrantsHomeKit(_ xml: String) -> Bool {
        guard let range = xml.range(of: "<key>com.apple.developer.homekit</key>") else { return false }
        let rest = xml[range.upperBound...].prefix(80)
        return rest.contains("<true/>")
    }
}
