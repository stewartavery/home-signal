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
        var trace: [String] = []
        var featuresKnown = false
        var invoked: [String: AnyObject] = [:]

        for pair in zeroArg {
            let key = "\(pair.0).\(pair.1)"
            let object = callClass(pair.0, pair.1, called: &called)
            if let object { invoked[key] = object }
            if screenSelectors.contains(pair.1) {
                trace.append(describeContext(pair.0, pair.1, object))
            }
        }
        let screenObject = preferredScreen(invoked)
        if screenObject == nil {
            trace.append("screenContext=no reason=every shared screen-context selector returned nil")
        } else {
            trace.append("screenContext=yes")
        }
        trace.append(contentsOf: methodDump("AVOutputContext"))
        trace.append(contentsOf: methodDump("AVOutputDeviceDiscoverySession"))
        trace.append(contentsOf: methodDump("MRAVRoutingDiscoverySession"))

        for object in invoked.values {
            let read = readDevices(object, selectedIDs: ids(of: screenObject))
            featuresKnown = featuresKnown || read.known
            rawDevices.append(contentsOf: read.devices)
        }
        let masks: [UInt] = [1, 2, 4, 8, 16, 32, 64, 128, 256, 0xFFFF_FFFF]
        var sessions: [AnyObject] = []
        for mask in masks {
            if let session = allocFeatures("AVOutputDeviceDiscoverySession", "initWithDeviceFeatures:", mask, called: &called, encodings: &encodings, selectors: &selectors) {
                setMode(session, className: "AVOutputDeviceDiscoverySession", mode: 2, called: &called, encodings: &encodings, selectors: &selectors)
                sessions.append(session)
                trace.append("discovery AVOutputDeviceDiscoverySession mask=\(mask) mode=2 session=yes")
            }
            if let session = callClassUInt("MRAVRoutingDiscoverySession", "discoverySessionWithEndpointFeatures:", mask, called: &called) {
                setMode(session, className: "MRAVRoutingDiscoverySession", mode: 3, called: &called, encodings: &encodings, selectors: &selectors)
                sessions.append(session)
                trace.append("discovery MRAVRoutingDiscoverySession mask=\(mask) mode=3 session=yes")
            }
        }
        if !sessions.isEmpty {
            let until = Date().addingTimeInterval(4)
            while Date() < until {
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.25))
            }
        }
        for session in sessions {
            let read = readDevices(session, selectedIDs: ids(of: screenObject))
            featuresKnown = featuresKnown || read.known
            rawDevices.append(contentsOf: read.devices)
            trace.append("discoveryRead devices=\(read.devices.count)")
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
            ? "screenContext=no because every shared screen-context selector returned nil. Shared audio contexts do not mirror the display."
            : "A screen-mirroring context object was returned."
        var error: String?
        if let apply, let screenObject {
            let key = apply.identifier
            if apply.enabled {
                if let device = objects[key] {
                    error = setOutputDevice(screenObject, device, called: &called, encodings: &encodings, selectors: &selectors)
                } else {
                    error = "The routing device \(key) was not held for the screen context."
                }
            } else {
                error = "Clearing the screen route was not called. setOutputDevice:options:completionHandler: needs a device."
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
            called: called,
            trace: trace
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
        typealias Fn = @convention(c) (AnyClass, Selector) -> UnsafeMutableRawPointer?
        let fn = unsafeBitCast(method_getImplementation(method), to: Fn.self)
        called["\(className).\(selector)"] = true
        return adopt(fn(cls, NSSelectorFromString(selector)))
    }

    private static func callClassUInt(_ className: String, _ selector: String, _ value: UInt, called: inout [String: Bool]) -> AnyObject? {
        guard let cls = NSClassFromString(className), let method = class_getClassMethod(cls, NSSelectorFromString(selector)) else { return nil }
        guard let encoding = method_getTypeEncoding(method).map({ String(cString: $0) }), ObjCReturn.returnsObject(encoding) else { return nil }
        typealias Fn = @convention(c) (AnyClass, Selector, UInt) -> UnsafeMutableRawPointer?
        let fn = unsafeBitCast(method_getImplementation(method), to: Fn.self)
        called["\(className).\(selector)"] = true
        return adopt(fn(cls, NSSelectorFromString(selector), value))
    }

    private static func adopt(_ raw: UnsafeMutableRawPointer?) -> AnyObject? {
        guard let raw else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(raw).takeUnretainedValue()
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
        let identifier = text(object, "deviceID") ?? text(object, "identifier") ?? text(object, "uniqueIdentifier") ?? ""
        let deviceType = detail(object, "deviceType")
        let deviceSubtype = detail(object, "deviceSubtype") ?? detail(object, "deviceSubType")
        let featuresText = detail(object, "features") ?? detail(object, "deviceFeatures") ?? ""
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
        return (RouteCandidate(name: name, identifier: identifier, video: video, screen: screen, selected: selected, local: local, deviceType: deviceType ?? "", deviceSubtype: deviceSubtype ?? "", featuresText: featuresText), known)
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

    private static func detail(_ object: AnyObject, _ name: String) -> String? {
        let sel = NSSelectorFromString(name)
        guard let cls = object_getClass(object), let method = class_getInstanceMethod(cls, sel) else { return nil }
        guard let encoding = method_getTypeEncoding(method).map({ String(cString: $0) }) else { return nil }
        let type = ObjCReturn.primary(encoding)
        guard !type.isEmpty else { return nil }
        if type == "@" { return text(object, name) }
        if ObjCReturn.returnsBool(encoding) { return bool(object, name).map { $0 ? "1" : "0" } }
        typealias Signed = @convention(c) (AnyObject, Selector) -> Int64
        typealias Unsigned = @convention(c) (AnyObject, Selector) -> UInt64
        let imp = method_getImplementation(method)
        switch type {
        case "q", "i", "s", "l":
            let fn = unsafeBitCast(imp, to: Signed.self)
            return String(fn(object, sel))
        case "Q", "I", "S", "L":
            let fn = unsafeBitCast(imp, to: Unsigned.self)
            return String(fn(object, sel))
        default:
            return nil
        }
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
        typealias Fn = @convention(c) (AnyObject, Selector) -> UnsafeMutableRawPointer?
        let fn = unsafeBitCast(method_getImplementation(method), to: Fn.self)
        return adopt(fn(object, sel))
    }

    private static func preferredScreen(_ invoked: [String: AnyObject]) -> AnyObject? {
        let order = [
            "AVOutputContext.sharedSystemScreenContext",
            "AVOutputContext.sharedSystemScreenMirroringContext",
            "AVOutputContext.sharedScreenMirroringContext",
            "MRAVOutputContext.sharedSystemScreenContext",
            "MRAVOutputContext.sharedSystemScreenMirroringContext",
            "MRAVOutputContext.sharedScreenMirroringContext",
        ]
        for key in order {
            if let object = invoked[key] { return object }
        }
        return nil
    }

    private static func describeContext(_ className: String, _ selector: String, _ object: AnyObject?) -> String {
        guard let object else { return "screenReturn \(className).\(selector)=nil" }
        let kind = object_getClass(object).map { String(cString: class_getName($0)) } ?? "object"
        var parts = ["screenReturn \(className).\(selector)=\(kind)"]
        if let devices = arrayValue(object, "outputDevices") {
            parts.append("outputDevices=\(devices.count)")
        } else if instanceMethod(className, "outputDevices") != nil {
            parts.append("outputDevices=nil")
        }
        if let one = call(object, "outputDevice") {
            let oneKind = object_getClass(one).map { String(cString: class_getName($0)) } ?? "object"
            let oneName = text(one, "name") ?? text(one, "deviceName") ?? ""
            parts.append("outputDevice=\(oneKind)\(oneName.isEmpty ? "" : " name=\(oneName)")")
        } else if instanceMethod(className, "outputDevice") != nil {
            parts.append("outputDevice=nil")
        }
        if let ident = text(object, "contextID") ?? text(object, "contextUID") {
            parts.append("contextID=\(ident)")
        }
        return parts.joined(separator: " ")
    }

    private static func methodDump(_ className: String) -> [String] {
        guard let cls = NSClassFromString(className) else { return ["method \(className) missing"] }
        var lines = copyMethods(metaclass(cls), className, prefix: "+")
        lines.append(contentsOf: copyMethods(cls, className, prefix: "-"))
        if lines.isEmpty { lines.append("method \(className) empty") }
        return lines.sorted()
    }

    private static func metaclass(_ cls: AnyClass) -> AnyClass? {
        objc_getMetaClass(class_getName(cls)) as? AnyClass
    }

    private static func copyMethods(_ cls: AnyClass?, _ className: String, prefix: String) -> [String] {
        guard let cls else { return [] }
        var count: UInt32 = 0
        guard let list = class_copyMethodList(cls, &count) else { return [] }
        defer { free(list) }
        var lines: [String] = []
        for index in 0..<Int(count) {
            let method = list[index]
            let selName = String(cString: sel_getName(method_getName(method)))
            let encoding = method_getTypeEncoding(method).map { String(cString: $0) } ?? ""
            lines.append("method \(className) \(prefix)\(selName) encoding=\(encoding)")
        }
        return lines
    }

    private static func allocFeatures(_ className: String, _ selector: String, _ mask: UInt, called: inout [String: Bool], encodings: inout [String: String], selectors: inout [String: Bool]) -> AnyObject? {
        record(className: className, selector: selector, instance: true, selectors: &selectors, encodings: &encodings)
        record(className: className, selector: "alloc", instance: false, selectors: &selectors, encodings: &encodings)
        guard let allocated = callClass(className, "alloc", called: &called) else { return nil }
        return callInstanceUInt(allocated, selector, mask, className: className, called: &called)
    }

    private static func callInstanceUInt(_ object: AnyObject, _ selector: String, _ value: UInt, className: String, called: inout [String: Bool]) -> AnyObject? {
        let sel = NSSelectorFromString(selector)
        guard let cls = object_getClass(object), let method = class_getInstanceMethod(cls, sel) else { return nil }
        guard let encoding = method_getTypeEncoding(method).map({ String(cString: $0) }), ObjCReturn.returnsObject(encoding) else { return nil }
        typealias Fn = @convention(c) (AnyObject, Selector, UInt) -> UnsafeMutableRawPointer?
        let fn = unsafeBitCast(method_getImplementation(method), to: Fn.self)
        called["\(className).\(selector)"] = true
        return adopt(fn(object, sel, value))
    }

    private static func setMode(_ object: AnyObject, className: String, mode: Int, called: inout [String: Bool], encodings: inout [String: String], selectors: inout [String: Bool]) {
        let selector = "setDiscoveryMode:"
        record(className: className, selector: selector, instance: true, selectors: &selectors, encodings: &encodings)
        let sel = NSSelectorFromString(selector)
        guard let cls = object_getClass(object), let method = class_getInstanceMethod(cls, sel) else { return }
        guard let encoding = method_getTypeEncoding(method).map({ String(cString: $0) }), ObjCReturn.returnsVoid(encoding) else { return }
        typealias Fn = @convention(c) (AnyObject, Selector, Int) -> Void
        let fn = unsafeBitCast(method_getImplementation(method), to: Fn.self)
        called["\(className).\(selector)"] = true
        fn(object, sel, mode)
    }

    private static func setOutputDevice(_ context: AnyObject, _ device: AnyObject, called: inout [String: Bool], encodings: inout [String: String], selectors: inout [String: Bool]) -> String? {
        let selector = "setOutputDevice:options:completionHandler:"
        let className = object_getClass(context).map { String(cString: class_getName($0)) } ?? "AVOutputContext"
        record(className: className, selector: selector, instance: true, selectors: &selectors, encodings: &encodings)
        let sel = NSSelectorFromString(selector)
        guard let cls = object_getClass(context), let method = class_getInstanceMethod(cls, sel) else {
            return "The screen context has no setOutputDevice:options:completionHandler:."
        }
        guard let encoding = method_getTypeEncoding(method).map({ String(cString: $0) }), ObjCReturn.returnsVoid(encoding) else {
            let encoding = method_getTypeEncoding(method).map { String(cString: $0) } ?? ""
            return "setOutputDevice:options:completionHandler: encoding \(encoding) does not return void."
        }
        typealias Done = @convention(block) (AnyObject?) -> Void
        typealias Fn = @convention(c) (AnyObject, Selector, AnyObject, AnyObject?, Done) -> Void
        let fn = unsafeBitCast(method_getImplementation(method), to: Fn.self)
        let box = ApplyBox()
        let block: Done = { value in
            if let value, value is NSError {
                box.finish((value as? NSError)?.localizedDescription ?? "setOutputDevice failed")
            } else {
                box.finish(nil)
            }
        }
        called["\(className).\(selector)"] = true
        fn(context, sel, device, nil, block)
        if box.semaphore.wait(timeout: .now() + 8) == .timedOut {
            return "setOutputDevice:options:completionHandler: timed out."
        }
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
        if finished.wait(timeout: .now() + 25) == .timedOut {
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
