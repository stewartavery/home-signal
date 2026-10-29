#if os(macOS)
import Darwin
import Foundation
import HomeSignalCore
import ObjectiveC

// AVFoundation and MediaRemote are loaded with dlopen so this binary does not link them.
public struct RuntimeMediaRoutes: MediaRouteProbing {
    public init() {}

    public func snapshot() async -> RouteSnapshot {
        await MainActor.run { Collector.collect(apply: nil) }
    }

    public func setScreenRoute(identifier: String, enabled: Bool, dryRun: Bool) async throws -> RouteSnapshot {
        if dryRun { return await snapshot() }
        let outcome = await MainActor.run { Collector.collect(apply: Apply(identifier: identifier, enabled: enabled)) }
        if let error = outcome.error {
            throw HomeSignalError.backend(error, hint: RouteSelection.debugText(outcome.snapshot))
        }
        return outcome.snapshot
    }
}

public struct MacSessionLock: SessionLockReading {
    public init() {}

    public func isScreenLocked() -> Bool {
        SessionLockText.isLocked(session: SessionFlags.dictionary(), consoleLocked: SessionFlags.consoleLocked())
    }
}

private struct Apply: Sendable {
    var identifier: String
    var enabled: Bool
}

private struct CollectResult: Sendable {
    var snapshot: RouteSnapshot
    var error: String?
}

private enum Collector {
    static let classNames = [
        "AVOutputDeviceDiscoverySession",
        "AVOutputDevice",
        "AVOutputContext",
        "AVRouteDetector",
        "MRAVOutputContext",
        "MRAVOutputDevice",
        "MRAVRoutingDiscoverySession",
        "MRAVEndpoint",
    ]

    static let zeroArg: [(String, String)] = [
        ("AVOutputDeviceDiscoverySession", "sharedAudioSession"),
        ("AVOutputContext", "sharedSystemAudioContext"),
        ("AVOutputContext", "sharedSystemScreenMirroringContext"),
        ("AVOutputContext", "sharedSystemScreenContext"),
        ("AVOutputContext", "sharedScreenMirroringContext"),
        ("MRAVOutputContext", "sharedSystemAudioContext"),
        ("MRAVOutputContext", "sharedSystemScreenMirroringContext"),
        ("MRAVOutputContext", "sharedScreenMirroringContext"),
        ("MRAVOutputContext", "sharedSystemScreenContext"),
    ]

    static let screenSelectors = [
        "sharedSystemScreenMirroringContext",
        "sharedScreenMirroringContext",
        "sharedSystemScreenContext",
    ]

    static func collect(apply: Apply?) -> CollectResult {
        loadFrameworks()
        var classes: [String: Bool] = [:]
        var selectors: [String: Bool] = [:]
        for name in classNames {
            classes[name] = NSClassFromString(name) != nil
        }
        for pair in zeroArg {
            let key = "\(pair.0).\(pair.1)"
            selectors[key] = classMethod(pair.0, pair.1) != nil
        }
        selectors["MRAVRoutingDiscoverySession.discoverySessionWithEndpointFeatures:"] = classMethod("MRAVRoutingDiscoverySession", "discoverySessionWithEndpointFeatures:") != nil
        selectors["MRAVRoutingDiscoverySession.discoverySessionWithEndpointFeatures:enableThrottling:"] = classMethod("MRAVRoutingDiscoverySession", "discoverySessionWithEndpointFeatures:enableThrottling:") != nil
        selectors["MRAVOutputContext.setOutputDevices:initiator:withReplyQueue:completion:"] = instanceMethod("MRAVOutputContext", "setOutputDevices:initiator:withReplyQueue:completion:") != nil
        selectors["AVOutputContext.setOutputDevice:options:completionHandler:"] = instanceMethod("AVOutputContext", "setOutputDevice:options:completionHandler:") != nil

        var rawDevices: [(object: AnyObject, candidate: RouteCandidate)] = []
        var screenObject: AnyObject?
        var featuresKnown = false

        for pair in zeroArg where screenSelectors.contains(pair.1) {
            if screenObject == nil, let object = callClass(pair.0, pair.1) {
                screenObject = object
            }
        }
        for pair in zeroArg {
            guard let object = callClass(pair.0, pair.1) else { continue }
            let read = readDevices(object, selectedIDs: ids(of: screenObject))
            featuresKnown = featuresKnown || read.known
            rawDevices.append(contentsOf: read.devices)
        }
        if let session = callClassUInt("MRAVRoutingDiscoverySession", "discoverySessionWithEndpointFeatures:", 7) {
            let read = readDevices(session, selectedIDs: ids(of: screenObject))
            featuresKnown = featuresKnown || read.known
            rawDevices.append(contentsOf: read.devices)
        }
        if let session = callClassUIntBool("MRAVRoutingDiscoverySession", "discoverySessionWithEndpointFeatures:enableThrottling:", 7, false) {
            let read = readDevices(session, selectedIDs: ids(of: screenObject))
            featuresKnown = featuresKnown || read.known
            rawDevices.append(contentsOf: read.devices)
        }

        var seen: Set<String> = []
        var devices: [RouteCandidate] = []
        var objects: [String: AnyObject] = [:]
        for item in rawDevices {
            let key = item.candidate.identifier.isEmpty ? item.candidate.name : item.candidate.identifier
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            devices.append(item.candidate)
            objects[key] = item.object
        }

        let note = screenObject == nil
            ? "No screen-mirroring context was found. Shared audio and video output contexts do not mirror the display."
            : "A screen-mirroring context was found."
        var error: String?
        if let apply, let screenObject {
            let key = apply.identifier
            if apply.enabled {
                if let device = objects[key] {
                    error = setDevices(screenObject, [device])
                } else {
                    error = "The routing device \(key) was not held for the screen context."
                }
            } else {
                error = setDevices(screenObject, [])
            }
        }
        let snapshot = RouteSnapshot(
            classes: classes,
            selectors: selectors,
            devices: devices,
            screenContext: screenObject != nil,
            featuresKnown: featuresKnown,
            note: note
        )
        return CollectResult(snapshot: snapshot, error: error)
    }

    private static func loadFrameworks() {
        _ = dlopen("/System/Library/Frameworks/AVFoundation.framework/AVFoundation", RTLD_LAZY)
        _ = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY)
    }

    private static func classMethod(_ className: String, _ selector: String) -> Method? {
        guard let cls = NSClassFromString(className) else { return nil }
        return class_getClassMethod(cls, NSSelectorFromString(selector))
    }

    private static func instanceMethod(_ className: String, _ selector: String) -> Method? {
        guard let cls = NSClassFromString(className) else { return nil }
        return class_getInstanceMethod(cls, NSSelectorFromString(selector))
    }

    private static func callClass(_ className: String, _ selector: String) -> AnyObject? {
        guard let cls = NSClassFromString(className), let method = class_getClassMethod(cls, NSSelectorFromString(selector)) else { return nil }
        typealias Fn = @convention(c) (AnyObject, Selector) -> AnyObject?
        let fn = unsafeBitCast(method_getImplementation(method), to: Fn.self)
        return fn(meta(cls), NSSelectorFromString(selector))
    }

    private static func callClassUInt(_ className: String, _ selector: String, _ value: UInt) -> AnyObject? {
        guard let cls = NSClassFromString(className), let method = class_getClassMethod(cls, NSSelectorFromString(selector)) else { return nil }
        typealias Fn = @convention(c) (AnyObject, Selector, UInt) -> AnyObject?
        let fn = unsafeBitCast(method_getImplementation(method), to: Fn.self)
        return fn(meta(cls), NSSelectorFromString(selector), value)
    }

    private static func callClassUIntBool(_ className: String, _ selector: String, _ value: UInt, _ flag: Bool) -> AnyObject? {
        guard let cls = NSClassFromString(className), let method = class_getClassMethod(cls, NSSelectorFromString(selector)) else { return nil }
        typealias Fn = @convention(c) (AnyObject, Selector, UInt, UInt8) -> AnyObject?
        let fn = unsafeBitCast(method_getImplementation(method), to: Fn.self)
        return fn(meta(cls), NSSelectorFromString(selector), value, flag ? 1 : 0)
    }

    private static func meta(_ cls: AnyClass) -> AnyObject {
        unsafeBitCast(cls, to: AnyObject.self)
    }

    private static func readDevices(_ root: AnyObject, selectedIDs: Set<String>) -> (devices: [(object: AnyObject, candidate: RouteCandidate)], known: Bool) {
        let array = arrayValue(root, "availableOutputDevices") ?? arrayValue(root, "outputDevices") ?? arrayValue(root, "availableEndpoints") ?? []
        var known = false
        var devices: [(object: AnyObject, candidate: RouteCandidate)] = []
        for item in array {
            let parsed = candidate(item, selectedIDs: selectedIDs)
            known = known || parsed.known
            if !parsed.candidate.name.isEmpty {
                devices.append((item, parsed.candidate))
            }
        }
        return (devices, known)
    }

    private static func candidate(_ object: AnyObject, selectedIDs: Set<String>) -> (candidate: RouteCandidate, known: Bool) {
        let name = text(object, "name") ?? text(object, "deviceName") ?? ""
        let identifier = text(object, "identifier") ?? text(object, "deviceID") ?? text(object, "uniqueIdentifier") ?? ""
        var video = false
        var screen = false
        var known = false
        if let flag = bool(object, "supportsScreenMirroring") {
            screen = flag
            known = true
        }
        if let flag = bool(object, "canMirrorScreen") {
            screen = screen || flag
            known = true
        }
        if let flag = bool(object, "canPlayVideo") {
            video = flag
            known = true
        }
        if let model = text(object, "modelID")?.lowercased() {
            known = true
            if model.contains("tv") || model.contains("display") || model.contains("screen") {
                video = true
            }
        }
        let local = bool(object, "isLocalDevice") ?? false
        let selected = !identifier.isEmpty && selectedIDs.contains(identifier)
        return (RouteCandidate(name: name, identifier: identifier, video: video, screen: screen, selected: selected, local: local), known)
    }

    private static func ids(of object: AnyObject?) -> Set<String> {
        guard let object else { return [] }
        let array = arrayValue(object, "outputDevices") ?? []
        var ids: Set<String> = []
        for item in array {
            if let identifier = text(item, "identifier") ?? text(item, "deviceID"), !identifier.isEmpty {
                ids.insert(identifier)
            }
        }
        return ids
    }

    private static func arrayValue(_ object: AnyObject, _ name: String) -> [AnyObject]? {
        guard let value = call(object, name) else { return nil }
        if let array = value as? [AnyObject] { return array }
        if let array = value as? NSArray { return array.compactMap { $0 as AnyObject } }
        return nil
    }

    private static func text(_ object: AnyObject, _ name: String) -> String? {
        guard let value = call(object, name) as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func bool(_ object: AnyObject, _ name: String) -> Bool? {
        let sel = NSSelectorFromString(name)
        guard let cls = object_getClass(object), let method = class_getInstanceMethod(cls, sel) else { return nil }
        typealias Fn = @convention(c) (AnyObject, Selector) -> UInt8
        let fn = unsafeBitCast(method_getImplementation(method), to: Fn.self)
        return fn(object, sel) != 0
    }

    private static func call(_ object: AnyObject, _ name: String) -> AnyObject? {
        let sel = NSSelectorFromString(name)
        guard let cls = object_getClass(object), let method = class_getInstanceMethod(cls, sel) else { return nil }
        typealias Fn = @convention(c) (AnyObject, Selector) -> AnyObject?
        let fn = unsafeBitCast(method_getImplementation(method), to: Fn.self)
        return fn(object, sel)
    }

    private static func setDevices(_ context: AnyObject, _ devices: [AnyObject]) -> String? {
        let name = "setOutputDevices:initiator:withReplyQueue:completion:"
        let sel = NSSelectorFromString(name)
        guard let method = class_getInstanceMethod(object_getClass(context), sel) else {
            return "The screen context has no setOutputDevices:initiator:withReplyQueue:completion:."
        }
        typealias Done = @convention(block) (NSError?) -> Void
        typealias Fn = @convention(c) (AnyObject, Selector, NSArray, AnyObject?, DispatchQueue, Done) -> Void
        let fn = unsafeBitCast(method_getImplementation(method), to: Fn.self)
        let box = ApplyBox()
        let block: Done = { error in
            box.finish(error?.localizedDescription)
        }
        fn(context, sel, devices as NSArray, nil, DispatchQueue.global(qos: .userInitiated), block)
        let wait = box.semaphore.wait(timeout: .now() + 8)
        if wait == .timedOut { return "Setting the screen route timed out." }
        return box.error
    }
}

private final class ApplyBox: @unchecked Sendable {
    let semaphore = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    var error: String?
    private var finished = false

    func finish(_ error: String?) {
        lock.lock()
        defer { lock.unlock() }
        if finished { return }
        finished = true
        self.error = error
        semaphore.signal()
    }
}

private enum SessionFlags {
    static func dictionary() -> [String: String] {
        _ = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY)
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGSessionCopyCurrentDictionary") else { return [:] }
        typealias Copy = @convention(c) () -> Unmanaged<CFDictionary>?
        let copy = unsafeBitCast(symbol, to: Copy.self)
        guard let raw = copy()?.takeRetainedValue() else { return [:] }
        var result: [String: String] = [:]
        let dict = raw as NSDictionary
        for case let key as Any in dict.allKeys {
            let name = (key as? String) ?? String(describing: key)
            let value = dict.object(forKey: key)
            if let number = value as? NSNumber {
                result[name] = number.boolValue ? "true" : "false"
            } else if let text = value as? String {
                result[name] = text
            }
        }
        return result
    }

    static func consoleLocked() -> String? {
        guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY) else { return nil }
        typealias FromPath = @convention(c) (UInt32, UnsafePointer<CChar>) -> UInt32
        typealias Prop = @convention(c) (UInt32, CFString, CFAllocator?) -> Unmanaged<CFTypeRef>?
        typealias Release = @convention(c) (UInt32) -> Int32
        guard let fromSym = dlsym(handle, "IORegistryEntryFromPath"),
              let propSym = dlsym(handle, "IORegistryEntryCreateCFProperty"),
              let releaseSym = dlsym(handle, "IOObjectRelease") else { return nil }
        let fromPath = unsafeBitCast(fromSym, to: FromPath.self)
        let prop = unsafeBitCast(propSym, to: Prop.self)
        let release = unsafeBitCast(releaseSym, to: Release.self)
        for path in ["IOService:/IOResources/IODisplayWrangler", "IOService:/IOResources/IOConsoleUsers"] {
            let entry = path.withCString { fromPath(0, $0) }
            if entry == 0 { continue }
            defer { _ = release(entry) }
            guard let value = prop(entry, "IOConsoleLocked" as CFString, nil)?.takeRetainedValue() else { continue }
            if let number = value as? NSNumber { return number.boolValue ? "true" : "false" }
        }
        return nil
    }
}
#endif
