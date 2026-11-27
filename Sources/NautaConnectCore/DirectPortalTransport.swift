import dnssd
import Foundation
import Network
import Security

/// Wire-level HTTP/1.1 serialization and response parsing used when bypassing
/// a system VPN tunnel over a raw TLS `NWConnection`.
enum HTTPWireCodec {
    struct Response: Equatable {
        let statusCode: Int
        let headers: [(name: String, value: String)]
        let body: Data

        static func == (lhs: Response, rhs: Response) -> Bool {
            lhs.statusCode == rhs.statusCode
                && lhs.body == rhs.body
                && lhs.headers.count == rhs.headers.count
                && zip(lhs.headers, rhs.headers).allSatisfy { $0.name == $1.name && $0.value == $1.value }
        }

        func firstHeader(_ name: String) -> String? {
            let target = name.lowercased()
            return headers.first { $0.name.lowercased() == target }?.value
        }

        func headerValues(_ name: String) -> [String] {
            let target = name.lowercased()
            return headers
                .filter { $0.name.lowercased() == target }
                .map(\.value)
        }
    }

    enum ChunkedResult: Equatable {
        case complete(Data)
        case incomplete
        case malformed
    }

    static func serializeRequest(
        method: String,
        url: URL,
        headers: [(String, String)],
        body: Data? = nil
    ) -> Data {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let rawPath = components?.percentEncodedPath ?? ""
        let path = rawPath.isEmpty ? "/" : rawPath
        let query = components?.percentEncodedQuery.map { "?\($0)" } ?? ""
        let target = "\(path)\(query)"

        var lines: [String] = ["\(method) \(target) HTTP/1.1"]
        for (name, value) in headers {
            lines.append("\(name): \(value)")
        }
        if let body {
            lines.append("Content-Length: \(body.count)")
        }

        var data = Data((lines.joined(separator: "\r\n") + "\r\n\r\n").utf8)
        if let body {
            data.append(body)
        }
        return data
    }

    static func splitHeaderAndBody(in buffer: Data) -> (headerData: Data, bodyStart: Int)? {
        if let range = buffer.range(of: Data([13, 10, 13, 10])) {
            return (buffer.subdata(in: buffer.startIndex..<range.lowerBound), range.upperBound)
        }
        if let range = buffer.range(of: Data([10, 10])) {
            return (buffer.subdata(in: buffer.startIndex..<range.lowerBound), range.upperBound)
        }
        return nil
    }

    static func parseHeaderBlock(_ headerData: Data) -> (statusCode: Int, headers: [(name: String, value: String)])? {
        let raw = String(decoding: headerData, as: UTF8.self)
        let lines = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        guard let statusLine = lines.first else { return nil }

        let parts = statusLine.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard parts.count >= 2,
              parts[0].uppercased().hasPrefix("HTTP/"),
              let statusCode = Int(parts[1]) else {
            return nil
        }

        var headers: [(name: String, value: String)] = []
        for line in lines.dropFirst() {
            guard !line.isEmpty, let colon = line.firstIndex(of: ":") else { continue }
            let name = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            if !name.isEmpty {
                headers.append((name: name, value: value))
            }
        }
        return (statusCode, headers)
    }

    static func isResponseComplete(
        buffer: Data,
        bodyStart: Int,
        headers: [(name: String, value: String)]
    ) -> Bool {
        let bodySlice = buffer[bodyStart...]
        if isChunked(headers: headers) {
            if case .complete = decodeChunked(Data(bodySlice)) {
                return true
            }
            return false
        }
        if let length = contentLength(headers: headers) {
            return bodySlice.count >= length
        }
        return false
    }

    static func parseResponse(from buffer: Data) -> Response? {
        guard let split = splitHeaderAndBody(in: buffer),
              let parsedHeader = parseHeaderBlock(split.headerData) else {
            return nil
        }

        let rawBody = Data(buffer[split.bodyStart...])
        let body: Data
        if isChunked(headers: parsedHeader.headers) {
            switch decodeChunked(rawBody) {
            case .complete(let decoded):
                body = decoded
            case .incomplete, .malformed:
                return nil
            }
        } else if let length = contentLength(headers: parsedHeader.headers) {
            guard rawBody.count >= length else { return nil }
            body = rawBody.prefix(length)
        } else {
            body = rawBody
        }

        return Response(statusCode: parsedHeader.statusCode, headers: parsedHeader.headers, body: body)
    }

    static func decodeChunked(_ data: Data) -> ChunkedResult {
        var output = Data()
        var index = data.startIndex
        let crlf = Data([13, 10])

        while index < data.endIndex {
            guard let lineEnd = data[index...].range(of: crlf) else {
                return .incomplete
            }
            let sizeLine = String(decoding: data[index..<lineEnd.lowerBound], as: UTF8.self)
            let hexPart = sizeLine.split(separator: ";", maxSplits: 1).first.map(String.init) ?? ""
            guard let chunkSize = Int(hexPart.trimmingCharacters(in: .whitespaces), radix: 16),
                  chunkSize >= 0 else {
                return .malformed
            }

            index = lineEnd.upperBound
            if chunkSize == 0 {
                // Consume optional trailer headers until the empty terminating line.
                if data[index...].starts(with: crlf) {
                    return .complete(output)
                }
                if let trailerEnd = data[index...].range(of: Data([13, 10, 13, 10])) {
                    _ = trailerEnd
                    return .complete(output)
                }
                return .incomplete
            }

            guard data.distance(from: index, to: data.endIndex) >= chunkSize + 2 else {
                return .incomplete
            }
            let chunkEnd = data.index(index, offsetBy: chunkSize)
            output.append(data[index..<chunkEnd])

            let afterChunk = data.index(chunkEnd, offsetBy: 2)
            guard data[chunkEnd..<afterChunk] == crlf else {
                return .malformed
            }
            index = afterChunk
        }

        return .incomplete
    }

    static func parseCookies(from setCookieValues: [String]) -> [String: String] {
        var cookies: [String: String] = [:]
        for header in setCookieValues {
            let pair = header.split(separator: ";", maxSplits: 1).first.map(String.init) ?? header
            guard let eq = pair.firstIndex(of: "=") else { continue }
            let name = String(pair[..<eq]).trimmingCharacters(in: .whitespaces)
            let value = String(pair[pair.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            if !name.isEmpty {
                cookies[name] = value
            }
        }
        return cookies
    }

    private static func isChunked(headers: [(name: String, value: String)]) -> Bool {
        headers.contains {
            $0.name.lowercased() == "transfer-encoding"
                && $0.value.lowercased().contains("chunked")
        }
    }

    private static func contentLength(headers: [(name: String, value: String)]) -> Int? {
        guard let raw = headers.first(where: { $0.name.lowercased() == "content-length" })?.value else {
            return nil
        }
        guard let length = Int(raw.trimmingCharacters(in: .whitespaces)), length >= 0 else {
            return nil
        }
        return length
    }
}

/// Routes HTTPS requests directly over an active physical network interface
/// (Wi-Fi or Ethernet), bypassing system VPN tunnels (`utun`/`ipsec`/`ppp`).
actor DirectPortalTransport {
    enum TransportError: Error {
        case noPhysicalInterface
        case connectionFailed
        case timedOut
        case invalidResponse
    }

    private var cookies: [String: String] = [:]
    private let userAgent: String
    private let acceptHeader: String

    init(userAgent: String, acceptHeader: String) {
        self.userAgent = userAgent
        self.acceptHeader = acceptHeader
    }

    /// Returns a physical interface when the default system route uses a tunnel (`.other`).
    /// Returns `nil` when no VPN tunnel is active on the default path.
    static func physicalInterfaceIfVPNActive() async -> NWInterface? {
        let defaultPath = await currentPath(prohibitedInterfaceTypes: [])
        let usesTunnel = defaultPath.usesInterfaceType(.other)
            || defaultPath.availableInterfaces.contains { $0.type == .other }
        guard usesTunnel else { return nil }

        let directPath = await currentPath(prohibitedInterfaceTypes: [.other])
        if let physical = directPath.availableInterfaces.first(where: { isPhysical($0) }) {
            return physical
        }
        return defaultPath.availableInterfaces.first(where: { isPhysical($0) })
    }

    func send(
        method: String,
        url: URL,
        formBody: Data? = nil,
        timeout: TimeInterval,
        via interface: NWInterface
    ) async throws -> (data: Data, statusCode: Int) {
        var currentMethod = method
        var currentURL = url
        var currentBody = formBody

        for _ in 0..<5 {
            let response = try await sendOnce(
                method: currentMethod,
                url: currentURL,
                formBody: currentBody,
                timeout: timeout,
                via: interface
            )

            let parsedCookies = HTTPWireCodec.parseCookies(from: response.headerValues("Set-Cookie"))
            for (name, value) in parsedCookies {
                cookies[name] = value
            }

            if (301...308).contains(response.statusCode),
               let location = response.firstHeader("Location"),
               let nextURL = URL(string: location, relativeTo: currentURL)?.absoluteURL,
               nextURL.scheme?.lowercased() == "https",
               nextURL.host?.lowercased() == currentURL.host?.lowercased() {
                if response.statusCode == 301 || response.statusCode == 302 || response.statusCode == 303 {
                    currentMethod = "GET"
                    currentBody = nil
                }
                currentURL = nextURL
                continue
            }

            return (response.body, response.statusCode)
        }

        throw TransportError.invalidResponse
    }

    private func sendOnce(
        method: String,
        url: URL,
        formBody: Data?,
        timeout: TimeInterval,
        via interface: NWInterface
    ) async throws -> HTTPWireCodec.Response {
        guard let host = url.host else {
            throw TransportError.invalidResponse
        }
        let port = UInt16(url.port ?? 443)
        let hostHeader = url.port.map { "\(host):\($0)" } ?? host

        var headers: [(String, String)] = [
            ("Host", hostHeader),
            ("User-Agent", userAgent),
            ("Accept", acceptHeader),
            ("Accept-Encoding", "identity"),
            ("Connection", "close"),
        ]
        if !cookies.isEmpty {
            let cookieValue = cookies
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: "; ")
            headers.append(("Cookie", cookieValue))
        }
        if formBody != nil {
            headers.append(("Content-Type", "application/x-www-form-urlencoded"))
        }

        let payload = HTTPWireCodec.serializeRequest(
            method: method,
            url: url,
            headers: headers,
            body: formBody
        )

        // Resolve via the physical interface's DNS first so VPN-injected DNS servers
        // (e.g. 1.1.1.1 inside a WireGuard tunnel) cannot shadow the portal address.
        let resolvedIP = await resolveHost(host, interfaceIndex: UInt32(interface.index), timeout: min(timeout, 3.0))
        let endpointHost = resolvedIP.map { NWEndpoint.Host($0) } ?? NWEndpoint.Host(host)
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            throw TransportError.invalidResponse
        }

        let tlsOptions = NWProtocolTLS.Options()
        // Keep full TLS SNI and certificate hostname verification against the portal hostname.
        sec_protocol_options_set_tls_server_name(tlsOptions.securityProtocolOptions, host)

        let parameters = NWParameters(tls: tlsOptions, tcp: .init())
        parameters.requiredInterface = interface
        parameters.prohibitedInterfaceTypes = [.other]

        let connection = NWConnection(to: .hostPort(host: endpointHost, port: endpointPort), using: parameters)
        return try await execute(connection: connection, payload: payload, timeout: timeout)
    }

    private func execute(
        connection: NWConnection,
        payload: Data,
        timeout: TimeInterval
    ) async throws -> HTTPWireCodec.Response {
        try await withCheckedThrowingContinuation { continuation in
            let queue = DispatchQueue(label: "com.nautaconnect.direct-http")
            let attempt = ConnectionAttempt(
                connection: connection,
                queue: queue,
                continuation: continuation
            )
            attempt.start(payload: payload, timeout: timeout)
        }
    }

    // MARK: - Physical interface & scoped DNS discovery

    private static func isPhysical(_ interface: NWInterface) -> Bool {
        interface.type == .wifi || interface.type == .wiredEthernet || interface.type == .cellular
    }

    private static func currentPath(prohibitedInterfaceTypes: [NWInterface.InterfaceType]) async -> NWPath {
        await withCheckedContinuation { continuation in
            let queue = DispatchQueue(label: "com.nautaconnect.path-probe")
            let monitor = prohibitedInterfaceTypes.isEmpty
                ? NWPathMonitor()
                : NWPathMonitor(prohibitedInterfaceTypes: prohibitedInterfaceTypes)
            let state = PathProbeState(monitor: monitor, continuation: continuation)
            monitor.pathUpdateHandler = { path in
                state.complete(with: path)
            }
            monitor.start(queue: queue)
            queue.asyncAfter(deadline: .now() + 0.5) { [monitor] in
                state.complete(with: monitor.currentPath)
            }
        }
    }

    private func resolveHost(_ host: String, interfaceIndex: UInt32, timeout: TimeInterval) async -> String? {
        await withCheckedContinuation { continuation in
            let queue = DispatchQueue(label: "com.nautaconnect.scoped-dns")
            let lookup = ScopedDNSLookup(queue: queue, continuation: continuation)
            lookup.start(host: host, interfaceIndex: interfaceIndex, timeout: timeout)
        }
    }
}

// All state transitions in PathProbeState run strictly on `queue` in `currentPath`.
private final class PathProbeState: @unchecked Sendable {
    private let monitor: NWPathMonitor
    private var continuation: CheckedContinuation<NWPath, Never>?

    init(monitor: NWPathMonitor, continuation: CheckedContinuation<NWPath, Never>) {
        self.monitor = monitor
        self.continuation = continuation
    }

    func complete(with path: NWPath) {
        guard let cont = continuation else { return }
        continuation = nil
        monitor.pathUpdateHandler = nil
        monitor.cancel()
        cont.resume(returning: path)
    }
}

// All callbacks and mutable state in ConnectionAttempt run strictly on `queue`.
private final class ConnectionAttempt: @unchecked Sendable {
    private let connection: NWConnection
    private let queue: DispatchQueue
    private var continuation: CheckedContinuation<HTTPWireCodec.Response, Error>?
    private var buffer = Data()
    private var timeoutWorkItem: DispatchWorkItem?
    private var requestSent = false

    init(
        connection: NWConnection,
        queue: DispatchQueue,
        continuation: CheckedContinuation<HTTPWireCodec.Response, Error>
    ) {
        self.connection = connection
        self.queue = queue
        self.continuation = continuation
    }

    func start(payload: Data, timeout: TimeInterval) {
        queue.async { [self] in
            let timer = DispatchWorkItem {
                self.finish(.failure(DirectPortalTransport.TransportError.timedOut))
            }
            timeoutWorkItem = timer
            queue.asyncAfter(deadline: .now() + timeout, execute: timer)

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard !self.requestSent else { return }
                    self.requestSent = true
                    self.sendRequest(payload)
                case .failed:
                    self.finish(.failure(DirectPortalTransport.TransportError.connectionFailed))
                case .cancelled:
                    self.finish(.failure(DirectPortalTransport.TransportError.connectionFailed))
                default:
                    break
                }
            }
            connection.start(queue: queue)
        }
    }

    private func sendRequest(_ payload: Data) {
        connection.send(content: payload, completion: .contentProcessed { error in
            if error != nil {
                self.finish(.failure(DirectPortalTransport.TransportError.connectionFailed))
                return
            }
            self.receiveNext()
        })
    }

    private func receiveNext() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
            if let data, !data.isEmpty {
                self.buffer.append(data)
            }

            if let split = HTTPWireCodec.splitHeaderAndBody(in: self.buffer),
               let header = HTTPWireCodec.parseHeaderBlock(split.headerData),
               HTTPWireCodec.isResponseComplete(buffer: self.buffer, bodyStart: split.bodyStart, headers: header.headers),
               let response = HTTPWireCodec.parseResponse(from: self.buffer) {
                self.finish(.success(response))
                return
            }

            if isComplete {
                if let response = HTTPWireCodec.parseResponse(from: self.buffer) {
                    self.finish(.success(response))
                } else {
                    self.finish(.failure(DirectPortalTransport.TransportError.invalidResponse))
                }
                return
            }

            if error != nil {
                self.finish(.failure(DirectPortalTransport.TransportError.connectionFailed))
                return
            }

            self.receiveNext()
        }
    }

    private func finish(_ result: Result<HTTPWireCodec.Response, Error>) {
        guard let cont = continuation else { return }
        continuation = nil
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        connection.stateUpdateHandler = nil
        connection.cancel()
        cont.resume(with: result)
    }
}

// All DNS-SD callbacks, timers, and deallocation run strictly on `queue`.
private final class ScopedDNSLookup: @unchecked Sendable {
    private let queue: DispatchQueue
    private var continuation: CheckedContinuation<String?, Never>?
    private var sdRef: DNSServiceRef?
    private var selfRef: Unmanaged<ScopedDNSLookup>?
    private var timeoutWorkItem: DispatchWorkItem?

    init(queue: DispatchQueue, continuation: CheckedContinuation<String?, Never>) {
        self.queue = queue
        self.continuation = continuation
    }

    func start(host: String, interfaceIndex: UInt32, timeout: TimeInterval) {
        queue.async { [self] in
            let retained = Unmanaged.passRetained(self)
            selfRef = retained

            var service: DNSServiceRef?
            let err = DNSServiceGetAddrInfo(
                &service,
                0,
                interfaceIndex,
                0,
                host,
                { _, _, _, errorCode, _, address, _, context in
                    guard let context else { return }
                    let lookup = Unmanaged<ScopedDNSLookup>.fromOpaque(context).takeUnretainedValue()
                    lookup.handleReply(errorCode: errorCode, address: address)
                },
                retained.toOpaque()
            )

            guard err == kDNSServiceErr_NoError, let service else {
                finish(nil)
                return
            }

            sdRef = service
            guard DNSServiceSetDispatchQueue(service, queue) == kDNSServiceErr_NoError else {
                finish(nil)
                return
            }

            let timer = DispatchWorkItem { [weak self] in
                self?.finish(nil)
            }
            timeoutWorkItem = timer
            queue.asyncAfter(deadline: .now() + timeout, execute: timer)
        }
    }

    private func handleReply(errorCode: DNSServiceErrorType, address: UnsafePointer<sockaddr>?) {
        guard errorCode == kDNSServiceErr_NoError,
              let address,
              let ipString = Self.ipString(from: address) else {
            finish(nil)
            return
        }
        finish(ipString)
    }

    private func finish(_ ip: String?) {
        guard let cont = continuation else { return }
        continuation = nil
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        if let service = sdRef {
            sdRef = nil
            DNSServiceRefDeallocate(service)
        }
        selfRef?.release()
        selfRef = nil
        cont.resume(returning: ip)
    }

    private static func ipString(from addr: UnsafePointer<sockaddr>) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        switch Int32(addr.pointee.sa_family) {
        case AF_INET:
            var sin = addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
            guard inet_ntop(AF_INET, &sin.sin_addr, &buffer, socklen_t(buffer.count)) != nil else {
                return nil
            }
            return String(cString: buffer)
        case AF_INET6:
            var sin6 = addr.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { $0.pointee }
            guard inet_ntop(AF_INET6, &sin6.sin6_addr, &buffer, socklen_t(buffer.count)) != nil else {
                return nil
            }
            return String(cString: buffer)
        default:
            return nil
        }
    }
}
