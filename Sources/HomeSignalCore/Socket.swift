import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

public final class StopFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false

    public init() {}

    public func stop() {
        lock.lock()
        stopped = true
        lock.unlock()
    }

    public func isStopped() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopped
    }
}

private func setAddressType(_ address: inout sockaddr_un) {
    // Darwin sockaddr_un starts with a length byte. Linux does not.
    withUnsafeMutableBytes(of: &address) { raw in
        #if canImport(Darwin)
        raw.storeBytes(of: UInt8(MemoryLayout<sockaddr_un>.size), toByteOffset: 0, as: UInt8.self)
        raw.storeBytes(of: UInt8(AF_UNIX), toByteOffset: 1, as: UInt8.self)
        #else
        raw.storeBytes(of: UInt16(AF_UNIX), toByteOffset: 0, as: UInt16.self)
        #endif
    }
}

private func posixBind(_ fd: Int32, _ pointer: UnsafePointer<sockaddr>, _ length: socklen_t) -> Int32 {
    bind(fd, pointer, length)
}

private func posixConnect(_ fd: Int32, _ pointer: UnsafePointer<sockaddr>, _ length: socklen_t) -> Int32 {
    connect(fd, pointer, length)
}

enum POSIXSocket {
    static func stream() throws -> Int32 {
        #if canImport(Darwin)
        let type = SOCK_STREAM
        #else
        let type = Int32(SOCK_STREAM.rawValue)
        #endif
        let fd = socket(AF_UNIX, type, 0)
        guard fd >= 0 else { throw errnoError("socket") }
        return fd
    }

    static func bind(_ fd: Int32, path: String) throws {
        var address = sockaddr_un()
        memset(&address, 0, MemoryLayout<sockaddr_un>.size)
        setAddressType(&address)
        let offset = MemoryLayout.offset(of: \sockaddr_un.sun_path) ?? 2
        let capacity = 104
        guard path.utf8.count + 1 <= capacity else {
            throw HomeSignalError.config(
                "Socket path is too long for a Unix socket (\(path.utf8.count) bytes).",
                hint: "Use a shorter path, for example /tmp/home-signal.sock."
            )
        }
        withUnsafeMutablePointer(to: &address) { pointer in
            let raw = UnsafeMutableRawPointer(pointer).advanced(by: offset)
            path.withCString { cString in
                _ = strcpy(raw.assumingMemoryBound(to: CChar.self), cString)
            }
        }
        let length = socklen_t(offset + path.utf8.count + 1)
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { pointer in
                posixBind(fd, pointer, length)
            }
        }
        guard result == 0 else { throw errnoError("bind \(path)") }
    }

    static func connect(_ fd: Int32, path: String) throws {
        var address = sockaddr_un()
        memset(&address, 0, MemoryLayout<sockaddr_un>.size)
        setAddressType(&address)
        let offset = MemoryLayout.offset(of: \sockaddr_un.sun_path) ?? 2
        withUnsafeMutablePointer(to: &address) { pointer in
            let raw = UnsafeMutableRawPointer(pointer).advanced(by: offset)
            path.withCString { cString in
                _ = strcpy(raw.assumingMemoryBound(to: CChar.self), cString)
            }
        }
        let length = socklen_t(offset + path.utf8.count + 1)
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { pointer in
                posixConnect(fd, pointer, length)
            }
        }
        guard result == 0 else {
            if errno == ENOENT || errno == ECONNREFUSED {
                throw HomeSignalError.daemonUnavailable(path)
            }
            throw HomeSignalError.daemonUnavailable(path)
        }
    }

    static func errnoError(_ what: String) -> HomeSignalError {
        HomeSignalError.backend("\(what) failed (errno \(errno)).")
    }
}

public enum UnixSocket {
    public static func request(path: String, body: Data, timeoutSeconds: Double) async throws -> Data {
        let path = path
        let body = body
        let timeoutSeconds = timeoutSeconds
        return try await Task.detached {
            try blockingRequest(path: path, body: body, timeoutSeconds: timeoutSeconds)
        }.value
    }

    public static func serve(
        path: String,
        stop: StopFlag,
        handler: @escaping @Sendable (Data) async -> Data
    ) async throws {
        let parent = (path as NSString).deletingLastPathComponent
        if !parent.isEmpty {
            try FileManager.default.createDirectory(atPath: parent, withIntermediateDirectories: true)
        }
        if FileManager.default.fileExists(atPath: path) {
            unlink(path)
        }
        let fd = try POSIXSocket.stream()
        do {
            try POSIXSocket.bind(fd, path: path)
        } catch {
            close(fd)
            throw error
        }
        #if canImport(Darwin)
        let backlog: Int32 = 16
        #else
        let backlog: Int32 = 16
        #endif
        guard listen(fd, backlog) == 0 else {
            close(fd)
            throw POSIXSocket.errnoError("listen")
        }
        defer {
            close(fd)
            unlink(path)
        }
        while !stop.isStopped(), !Task.isCancelled {
            var pollSet = pollfd()
            pollSet.fd = fd
            pollSet.events = Int16(POLLIN)
            let ready = poll(&pollSet, 1, 200)
            if ready <= 0 { continue }
            let client = accept(fd, nil, nil)
            if client < 0 { continue }
            let request = readUntilEOF(client)
            let response = await handler(request)
            writeAll(client, response)
            close(client)
        }
    }

    private static func blockingRequest(path: String, body: Data, timeoutSeconds: Double) throws -> Data {
        guard FileManager.default.fileExists(atPath: path) else {
            throw HomeSignalError.daemonUnavailable(path)
        }
        let fd = try POSIXSocket.stream()
        defer { close(fd) }
        do {
            try POSIXSocket.connect(fd, path: path)
        } catch {
            throw HomeSignalError.daemonUnavailable(path)
        }
        try writeAllThrowing(fd, body)
        #if canImport(Darwin)
        _ = shutdown(fd, SHUT_WR)
        #else
        _ = shutdown(fd, Int32(SHUT_WR))
        #endif
        let data = readUntilEOF(fd, timeoutSeconds: timeoutSeconds)
        if data.isEmpty {
            throw HomeSignalError.daemonUnavailable(path)
        }
        return data
    }

    private static func readUntilEOF(_ fd: Int32, timeoutSeconds: Double = 30) -> Data {
        var output = Data()
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        var buffer = [UInt8](repeating: 0, count: 8192)
        while Date() < deadline {
            var pollSet = pollfd()
            pollSet.fd = fd
            pollSet.events = Int16(POLLIN)
            let ready = poll(&pollSet, 1, 200)
            if ready == 0 { continue }
            if ready < 0 { break }
            let count = buffer.withUnsafeMutableBufferPointer { pointer -> Int in
                Int(read(fd, pointer.baseAddress, pointer.count))
            }
            if count <= 0 { break }
            output.append(contentsOf: buffer.prefix(count))
            if output.count > 8_000_000 { break }
        }
        return output
    }

    @discardableResult
    private static func writeAll(_ fd: Int32, _ data: Data) -> Bool {
        (try? writeAllThrowing(fd, data)) != nil
    }

    private static func writeAllThrowing(_ fd: Int32, _ data: Data) throws {
        try data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var sent = 0
            while sent < raw.count {
                let wrote = Int(write(fd, base.advanced(by: sent), raw.count - sent))
                if wrote < 0 {
                    throw POSIXSocket.errnoError("write")
                }
                if wrote == 0 { break }
                sent += wrote
            }
        }
    }
}

public struct SocketAgentClient: AgentSending {
    public var socketPath: String
    public var timeoutSeconds: Double

    public init(socketPath: String, timeoutSeconds: Double = 60) {
        self.socketPath = socketPath
        self.timeoutSeconds = timeoutSeconds
    }

    public func send(_ request: IPCRequest) async throws -> IPCResponse {
        let data = try IPCCodec.encodeRequest(request)
        let limit = request.method == IPCMethod.lightsBlink ? max(timeoutSeconds, 300) : timeoutSeconds
        let response = try await UnixSocket.request(path: socketPath, body: data, timeoutSeconds: limit)
        return try IPCCodec.decodeResponse(response)
    }
}
