import Foundation

/// Serves canned responses to `HTTPClient` sessions. Install with `protocolClasses: [MockURLProtocol.self]`.
final class MockURLProtocol: URLProtocol {
    struct Reply {
        var status: Int = 200
        var body: Data
        var contentType = "text/html; charset=iso-8859-1"
        var error: URLError?

        static func html(_ s: String, status: Int = 200) -> Reply {
            Reply(status: status, body: s.data(using: .isoLatin1)!)
        }

        static func fixture(_ name: String) -> Reply {
            Reply(body: Fixture.data(name))
        }

        static func failure(_ code: URLError.Code) -> Reply {
            Reply(body: Data(), error: URLError(code))
        }
    }

    struct Recorded {
        var method: String
        var url: URL
        var body: String?
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var handler: ((URLRequest, String?) -> Reply)?
    nonisolated(unsafe) private static var log: [Recorded] = []

    static func install(_ handler: @escaping (URLRequest, String?) -> Reply) {
        lock.lock(); defer { lock.unlock() }
        self.handler = handler
        log = []
    }

    static var requests: [Recorded] {
        lock.lock(); defer { lock.unlock() }
        return log
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = Self.readBody(request)
        Self.lock.lock()
        Self.log.append(Recorded(method: request.httpMethod ?? "GET", url: request.url!, body: body))
        let handler = Self.handler
        Self.lock.unlock()

        guard let reply = handler?(request, body) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        if let error = reply.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": reply.contentType])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func readBody(_ request: URLRequest) -> String? {
        if let data = request.httpBody { return String(data: data, encoding: .utf8) }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open(); defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let n = stream.read(&buffer, maxLength: buffer.count)
            if n <= 0 { break }
            data.append(buffer, count: n)
        }
        return String(data: data, encoding: .utf8)
    }
}

/// Routes the OPAC handshake to the captured pages and lets each test decide what the search POST returns.
enum OPACRoutes {
    static func handler(
        entry: MockURLProtocol.Reply = .fixture("opac_session_entry.html"),
        search: @escaping (String) -> MockURLProtocol.Reply,
        detail: @escaping (URL) -> MockURLProtocol.Reply = { _ in .fixture("opac_detail_cien_anos.html") }
    ) -> (URLRequest, String?) -> MockURLProtocol.Reply {
        { request, body in
            let url = request.url!.absoluteString
            if request.httpMethod == "POST" { return search(body ?? "") }
            if url.contains("ACC=165") { return detail(request.url!) }
            if url.contains("ACC=120") { return .fixture("opac_advanced_form.html") }
            if url.hasSuffix("abnetopac?ACC=101") { return entry }
            if url.contains("ACC=101") { return .html("<html><body>Inicio</body></html>") }
            return .html("not found", status: 404)
        }
    }
}
