#if os(macOS)
import Darwin
import Foundation
import HomeSignalCore
import ObjectiveC

// AVFoundation and MediaRemote are loaded with dlopen so this binary does not link them.
public struct RuntimeMediaRoutes: MediaRouteProbing {
    public init() {}

    public func snapshot() async -> RouteSnapshot {
        ProbeClient.run(arguments: []).snapshot
    }

    public func setScreenRoute(identifier: String, enabled: Bool, dryRun: Bool) async throws -> RouteSnapshot {
        if dryRun { return await snapshot() }
        let report = ProbeClient.run(arguments: ["set", identifier, enabled ? "on" : "off"])
        if let error = report.error {
            throw HomeSignalError.backend(error, hint: RouteSelection.debugText(report.snapshot))
        }
        return report.snapshot
    }
}

public enum MediaRouteProbeMain {
    public static func main() -> Never {
        let args = Array(CommandLine.arguments.dropFirst())
        let outcome: CollectResult
        if args.count >= 3, args[0] == "set" {
            outcome = Collector.collect(apply: Apply(identifier: args[1], enabled: args[2] == "on"))
        } else {
            outcome = Collector.collect(apply: nil)
        }
        let report = ProbeReport(snapshot: outcome.snapshot, error: outcome.error)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        if let data = try? encoder.encode(report) {
            FileHandle.standardOutput.write(data)
        }
        exit(outcome.error == nil ? 0 : 1)
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
        var encodings: [String: String] = [:]
        var called: [String: Bool] = [:]
        for name in classNames {
            classes[name] = NSClassFromString(name) != nil
        }
        for pair in zeroArg {
            record(className: pair.0, selector: pair.1, instance: false, selectors: &selectors, encodings: &encodings)
        }
        record(className: "MRAVRoutingDiscoverySession", selector: "discoverySessionWithEndpointFeatures:", instance: false, selectors: &selectors, encodings: &encodings)
        record(className: "MRAVRoutingDiscoverySession", selector: "discoverySessionWithEndpointFeatures:enableThrottling:", instance: false, selectors: &selectors, encodings: &encodings)
        record(className: "MRAVOutputContext", selector: "setOutputDevices:initiator:withReplyQueue:completion:", instance: true, selectors: &selectors, encodings: &encodings)
        record(className: "AVOutputContext", selector: "setOutputDevice:options:completionHandler:", instance: true, selectors: &selectors, encodings: &encodings)

        var rawDevices: [(object: AnyObject, candidate: RouteCandidate)] = []
        var screenObject: AnyObject?
        var featuresKnown = false

        for pair in zeroArg where screenSelectors.contains(pair.1) {
            if screenObject == nil, let object = callClass(pair.0, pair.1, called: &called) {
                screenObject = object
            }
        }
        for pair in zeroArg {
            guard let object = callClass(pair.0, pair.1, called: &called) else { continue }
            let read = readDevices(object, selectedIDs: ids(of: screenObject))
            featuresKnown = featuresKnown || read.known
            rawDevices.append(contentsOf: read.devices)
        }
        if let session = callClassUInt("MRAVRoutingDiscoverySession", "discoverySessionWithEndpointFeatures:", 7, called: &called) {
            let read = readDevices(session, selectedIDs: ids(of: screenObject))
            featuresKnown = featuresKnown || read.known
            rawDevices.append(contentsOf: read.devices)
        }
        if let session = callClassUIntBool("MRAVRoutingDiscoverySession", "discoverySessionWithEndpointFeatures:enableThrottling:", 7, false, called: &called) {
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
            note: note,
            encodings: encodings,
            called: called
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

    private static func record(className: String, selector: String, instance: Bool, selectors: inout [String: Bool], encodings: inout [String: String]) {
        let key = "\(className).\(selector)"
        let method = instance ? instanceMethod(className, selector) : classMethod(className, selector)
        selectors[key] = method != nil
        if let method, let raw = method_getTypeEncoding(method) {
            encodings[key] = String(cString: raw)
        }
    }

    private static func callClass(_ className: String, _ selector: String, called: inout [String: Bool]) -> AnyObject? {
        guard let cls = NSClassFromString(className), let method = class_getClassMethod(cls, NSSelectorFromString(selector)) else { return nil }
        guard let encoding = method_getTypeEncoding(method).map({ String(cString: $0) }), ObjCReturn.returnsObject(encoding) else { return nil }
        typealias Fn = @convention(c) (AnyClass, Selector) -> Unmanaged<AnyObject>?
        let fn = unsafeBitCast(method_getImplementation(method), to: Fn.self)
        called["\(className).\(selector)"] = true
        return fn(cls, NSSelectorFromString(selector))?.takeUnretainedValue()
    }

    private static func callClassUInt(_ className: String, _ selector: String, _ value: UInt, called: inout [String: Bool]) -> AnyObject? {
        guard let cls = NSClassFromString(className), let method = class_getClassMethod(cls, NSSelectorFromString(selector)) else { return nil }
        guard let encoding = method_getTypeEncoding(method).map({ String(cString: $0) }), ObjCReturn.returnsObject(encoding) else { return nil }
        typealias Fn = @convention(c) (AnyClass, Selector, UInt) -> Unmanaged<AnyObject>?
        let fn = unsafeBitCast(method_getImplementation(method), to: Fn.self)
        called["\(className).\(selector)"] = true
        return fn(cls, NSSelectorFromString(selector), value)?.takeUnretainedValue()
    }

    private static func callClassUIntBool(_ className: String, _ selector: String, _ value: UInt, _ flag: Bool, called: inout [String: Bool]) -> AnyObject? {
        guard let cls = NSClassFromString(className), let method = class_getClassMethod(cls, NSSelectorFromString(selector)) else { return nil }
        guard let encoding = method_getTypeEncoding(method).map({ String(cString: $0) }), ObjCReturn.returnsObject(encoding) else { return nil }
        typealias Fn = @convention(c) (AnyClass, Selector, UInt, UInt8) -> Unmanaged<AnyObject>?
        let fn = unsafeBitCast(method_getImplementation(method), to: Fn.self)
        called["\(className).\(selector)"] = true
        return fn(cls, NSSelectorFromString(selector), value, flag ? 1 : 0)?.takeUnretainedValue()
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
        guard let encoding = method_getTypeEncoding(method).map({ String(cString: $0) }), ObjCReturn.returnsBool(encoding) else { return nil }
        typealias Fn = @convention(c) (AnyObject, Selector) -> UInt8
        let fn = unsafeBitCast(method_getImplementation(method), to: Fn.self)
        return fn(object, sel) != 0
    }

    private static func call(_ object: AnyObject, _ name: String) -> AnyObject? {
        let sel = NSSelectorFromString(name)
        guard let cls = object_getClass(object), let method = class_getInstanceMethod(cls, sel) else { return nil }
        guard let encoding = method_getTypeEncoding(method).map({ String(cString: $0) }), ObjCReturn.returnsObject(encoding) else { return nil }
        typealias Fn = @convention(c) (AnyObject, Selector) -> Unmanaged<AnyObject>?
        let fn = unsafeBitCast(method_getImplementation(method), to: Fn.self)
        return fn(object, sel)?.takeUnretainedValue()
    }

    private static func setDevices(_ context: AnyObject, _ devices: [AnyObject]) -> String? {
        let name = "setOutputDevices:initiator:withReplyQueue:completion:"
        let sel = NSSelectorFromString(name)
        guard let method = class_getInstanceMethod(object_getClass(context), sel) else {
            return "The screen context has no setOutputDevices:initiator:withReplyQueue:completion:."
        }
        if let encoding = method_getTypeEncoding(method).map({ String(cString: $0) }), !ObjCReturn.returnsVoid(encoding) {
            return "setOutputDevices:initiator:withReplyQueue:completion: encoding \(encoding) does not return void."
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

private enum ProbeClient {
    static func run(arguments: [String]) -> ProbeReport {
        guard let binary = locate() else {
            let note = "home-signal-probe was not found next to the agent."
            return ProbeReport(snapshot: RouteSnapshot(classes: [:], selectors: [:], devices: [], screenContext: false, featuresKnown: false, note: note), error: note)
        }
        let process = Process()
        process.executableURL = binary
        process.arguments = arguments
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        do {
            try process.run()
        } catch {
            let note = "Could not start home-signal-probe."
            return ProbeReport(snapshot: RouteSnapshot(classes: [:], selectors: [:], devices: [], screenContext: false, featuresKnown: false, note: note), error: note)
        }
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        if finished.wait(timeout: .now() + 12) == .timedOut {
            process.terminate()
            _ = finished.wait(timeout: .now() + 2)
        }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let signaled = process.terminationReason == .uncaughtSignal
        return ProbeOutput.interpret(status: process.terminationStatus, signaled: signaled, stdout: data, stderr: err)
    }

    static func locate() -> URL? {
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        let sibling = executable.deletingLastPathComponent().appendingPathComponent("home-signal-probe")
        if FileManager.default.isExecutableFile(atPath: sibling.path) { return sibling }
        return nil
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
