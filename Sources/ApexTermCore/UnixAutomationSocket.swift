import Darwin
import Foundation

public enum UnixAutomationSocketError: Error, Equatable {
    case pathTooLong
    case socketCreation(errno: Int32)
    case bind(errno: Int32)
    case listen(errno: Int32)
    case connect(errno: Int32)
    case write(errno: Int32)
    case read(errno: Int32)
    case requestTooLarge
    case invalidResponse
}

public struct UnixPeerIdentityPolicy: Equatable, Sendable {
    public var allowedUserIDs: Set<UInt32>

    public init(allowedUserIDs: Set<UInt32>) {
        self.allowedUserIDs = allowedUserIDs
    }

    public func permits(userID: uid_t) -> Bool {
        allowedUserIDs.contains(UInt32(userID))
    }

    public static var currentUserOnly: UnixPeerIdentityPolicy {
        UnixPeerIdentityPolicy(allowedUserIDs: [UInt32(Darwin.geteuid())])
    }
}

public enum AutomationWireCodec {
    public static let maximumMessageBytes = 1_048_576

    public static func encodeRequest(_ request: AutomationRequest) throws -> Data {
        try lineEncoder().encode(request) + Data([0x0A])
    }

    public static func decodeRequest(_ data: Data) throws -> AutomationRequest {
        try lineDecoder().decode(AutomationRequest.self, from: trimmedLine(data))
    }

    public static func encodeResponse(_ response: AutomationResponse) throws -> Data {
        try lineEncoder().encode(response) + Data([0x0A])
    }

    public static func decodeResponse(_ data: Data) throws -> AutomationResponse {
        try lineDecoder().decode(AutomationResponse.self, from: trimmedLine(data))
    }

    private static func lineEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static func lineDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }

    private static func trimmedLine(_ data: Data) -> Data {
        var result = data
        while result.last == 0x0A || result.last == 0x0D {
            result.removeLast()
        }
        return result
    }
}

public struct AutomationRequestAuthorizer: Sendable {
    private let grantsByClient: [String: AutomationGrant]
    private let riskEngine: CommandRiskEngine

    public init(
        grants: [AutomationGrant],
        riskEngine: CommandRiskEngine = CommandRiskEngine()
    ) {
        self.grantsByClient = Dictionary(
            uniqueKeysWithValues: grants.map { ($0.clientID, $0) }
        )
        self.riskEngine = riskEngine
    }

    public func authorize(
        _ request: AutomationRequest,
        now: Date = Date()
    ) -> AutomationResponse {
        guard let grant = grantsByClient[request.clientID],
              grant.permits(request, now: now) else {
            return AutomationResponse(
                requestID: request.id,
                status: .denied,
                message: "Capability denied"
            )
        }

        if case let .runCommand(_, command) = request.action {
            let decision = riskEngine.evaluate(command)
            switch decision.level {
            case .requireApproval:
                return AutomationResponse(
                    requestID: request.id,
                    status: .denied,
                    message: "Foreground approval required: \(decision.ruleID ?? "risk")"
                )
            case .warn:
                return AutomationResponse(
                    requestID: request.id,
                    status: .accepted,
                    message: "Accepted with warning: \(decision.ruleID ?? "risk")"
                )
            case .allow:
                break
            }
        }

        return AutomationResponse(
            requestID: request.id,
            status: .accepted,
            message: "Authorized"
        )
    }
}

public final class UnixAutomationServer: @unchecked Sendable {
    public typealias Handler = @Sendable (AutomationRequest) -> AutomationResponse

    public let socketURL: URL
    private let handler: Handler
    private let peerIdentityPolicy: UnixPeerIdentityPolicy
    private let acceptQueue: DispatchQueue
    private let clientQueue: DispatchQueue
    private let stateLock = NSLock()
    private var listenerFD: Int32 = -1
    private var source: DispatchSourceRead?

    public init(
        socketURL: URL,
        peerIdentityPolicy: UnixPeerIdentityPolicy = .currentUserOnly,
        handler: @escaping Handler
    ) {
        self.socketURL = socketURL
        self.handler = handler
        self.peerIdentityPolicy = peerIdentityPolicy
        self.acceptQueue = DispatchQueue(
            label: "app.apexterm.automation.accept",
            qos: .userInitiated
        )
        self.clientQueue = DispatchQueue(
            label: "app.apexterm.automation.client",
            qos: .userInitiated,
            attributes: .concurrent
        )
    }

    deinit {
        stop()
    }

    public func start() throws {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard listenerFD < 0 else { return }

        let directory = socketURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        unlink(socketURL.path)

        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw UnixAutomationSocketError.socketCreation(errno: errno)
        }

        do {
            configureNoSigPipe(fd: fd)
            try bindUnixSocket(fd: fd, path: socketURL.path)
            guard Darwin.listen(fd, 32) == 0 else {
                throw UnixAutomationSocketError.listen(errno: errno)
            }
            _ = Darwin.fcntl(fd, F_SETFL, O_NONBLOCK)
            _ = Darwin.chmod(socketURL.path, S_IRUSR | S_IWUSR)

            listenerFD = fd
            let source = DispatchSource.makeReadSource(
                fileDescriptor: fd,
                queue: acceptQueue
            )
            source.setEventHandler { [weak self] in
                self?.acceptAvailableClients()
            }
            source.setCancelHandler {
                Darwin.close(fd)
            }
            self.source = source
            source.resume()
        } catch {
            Darwin.close(fd)
            unlink(socketURL.path)
            throw error
        }
    }

    public func stop() {
        stateLock.lock()
        let existingSource = source
        source = nil
        listenerFD = -1
        stateLock.unlock()

        existingSource?.cancel()
        unlink(socketURL.path)
    }

    private func acceptAvailableClients() {
        stateLock.lock()
        let fd = listenerFD
        stateLock.unlock()
        guard fd >= 0 else { return }

        while true {
            let clientFD = Darwin.accept(fd, nil, nil)
            if clientFD < 0 {
                if errno == EAGAIN || errno == EWOULDBLOCK {
                    return
                }
                return
            }

            var peerUserID: uid_t = 0
            var peerGroupID: gid_t = 0
            guard Darwin.getpeereid(clientFD, &peerUserID, &peerGroupID) == 0,
                  peerIdentityPolicy.permits(userID: peerUserID) else {
                Darwin.close(clientFD)
                continue
            }

            configureBlocking(fd: clientFD)
            configureNoSigPipe(fd: clientFD)
            clientQueue.async { [weak self] in
                self?.handleClient(fd: clientFD)
            }
        }
    }

    private func handleClient(fd: Int32) {
        defer { Darwin.close(fd) }
        configureTimeout(fd: fd, seconds: 2)

        do {
            let requestData = try readLine(fd: fd)
            let request = try AutomationWireCodec.decodeRequest(requestData)
            let response = handler(request)
            let responseData = try AutomationWireCodec.encodeResponse(response)
            try writeAll(fd: fd, data: responseData)
        } catch {
            let response = AutomationResponse(
                requestID: UUID(),
                status: .invalid,
                message: "Invalid automation request"
            )
            if let data = try? AutomationWireCodec.encodeResponse(response) {
                try? writeAll(fd: fd, data: data)
            }
        }
    }
}

public enum UnixAutomationClient {
    public static func send(
        _ request: AutomationRequest,
        to socketURL: URL,
        timeoutSeconds: Int = 20
    ) throws -> AutomationResponse {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw UnixAutomationSocketError.socketCreation(errno: errno)
        }
        defer { Darwin.close(fd) }
        configureNoSigPipe(fd: fd)
        configureTimeout(fd: fd, seconds: timeoutSeconds)

        try connectUnixSocket(fd: fd, path: socketURL.path)
        try writeAll(fd: fd, data: AutomationWireCodec.encodeRequest(request))
        _ = Darwin.shutdown(fd, SHUT_WR)
        let responseData = try readLine(fd: fd)
        return try AutomationWireCodec.decodeResponse(responseData)
    }
}

private func bindUnixSocket(fd: Int32, path: String) throws {
    var address = try makeUnixAddress(path: path)
    let length = unixAddressLength(path: path)
    let result = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            Darwin.bind(fd, $0, length)
        }
    }
    guard result == 0 else {
        throw UnixAutomationSocketError.bind(errno: errno)
    }
}

private func connectUnixSocket(fd: Int32, path: String) throws {
    var address = try makeUnixAddress(path: path)
    let length = unixAddressLength(path: path)
    let result = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            Darwin.connect(fd, $0, length)
        }
    }
    guard result == 0 else {
        throw UnixAutomationSocketError.connect(errno: errno)
    }
}

private func makeUnixAddress(path: String) throws -> sockaddr_un {
    var address = sockaddr_un()
    let bytes = Array(path.utf8CString)
    let capacity = MemoryLayout.size(ofValue: address.sun_path)
    guard bytes.count <= capacity else {
        throw UnixAutomationSocketError.pathTooLong
    }

    address.sun_family = sa_family_t(AF_UNIX)
    address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    path.withCString { source in
        withUnsafeMutablePointer(to: &address.sun_path) { tuplePointer in
            tuplePointer.withMemoryRebound(to: CChar.self, capacity: capacity) { destination in
                _ = Darwin.strlcpy(destination, source, capacity)
            }
        }
    }
    return address
}

private func unixAddressLength(path: String) -> socklen_t {
    socklen_t(MemoryLayout<sockaddr_un>.size)
}

private func configureBlocking(fd: Int32) {
    let flags = Darwin.fcntl(fd, F_GETFL)
    if flags >= 0 {
        _ = Darwin.fcntl(fd, F_SETFL, flags & ~O_NONBLOCK)
    }
}

private func configureNoSigPipe(fd: Int32) {
    var enabled: Int32 = 1
    withUnsafePointer(to: &enabled) { pointer in
        _ = Darwin.setsockopt(
            fd,
            SOL_SOCKET,
            SO_NOSIGPIPE,
            pointer,
            socklen_t(MemoryLayout<Int32>.size)
        )
    }
}

private func configureTimeout(fd: Int32, seconds: Int) {
    var timeout = timeval(tv_sec: seconds, tv_usec: 0)
    withUnsafePointer(to: &timeout) { pointer in
        _ = Darwin.setsockopt(
            fd,
            SOL_SOCKET,
            SO_RCVTIMEO,
            pointer,
            socklen_t(MemoryLayout<timeval>.size)
        )
        _ = Darwin.setsockopt(
            fd,
            SOL_SOCKET,
            SO_SNDTIMEO,
            pointer,
            socklen_t(MemoryLayout<timeval>.size)
        )
    }
}

private func readLine(fd: Int32) throws -> Data {
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 8_192)

    while data.count < AutomationWireCodec.maximumMessageBytes {
        let count = buffer.withUnsafeMutableBytes { rawBuffer in
            Darwin.read(fd, rawBuffer.baseAddress, rawBuffer.count)
        }
        if count > 0 {
            data.append(contentsOf: buffer.prefix(count))
            if data.contains(0x0A) {
                guard let newline = data.firstIndex(of: 0x0A) else { break }
                return Data(data[...newline])
            }
            continue
        }
        if count == 0 {
            return data
        }
        if errno == EINTR {
            continue
        }
        throw UnixAutomationSocketError.read(errno: errno)
    }

    throw UnixAutomationSocketError.requestTooLarge
}

private func writeAll(fd: Int32, data: Data) throws {
    try data.withUnsafeBytes { rawBuffer in
        guard let baseAddress = rawBuffer.baseAddress else { return }
        var offset = 0
        while offset < rawBuffer.count {
            let written = Darwin.write(
                fd,
                baseAddress.advanced(by: offset),
                rawBuffer.count - offset
            )
            if written > 0 {
                offset += written
                continue
            }
            if written < 0, errno == EINTR {
                continue
            }
            throw UnixAutomationSocketError.write(errno: errno)
        }
    }
}
