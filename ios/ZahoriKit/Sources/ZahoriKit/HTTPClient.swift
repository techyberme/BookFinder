import Foundation

/// Errors from the networking layer. Every network call in the app goes through `HTTPClient`.
public enum NetworkError: Error, Equatable, Sendable {
    case offline
    case timeout
    case http(status: Int)
    case transport(String)

    public var spanishDescription: String {
        switch self {
        case .offline: return String(localized: "Sin conexión a Internet", bundle: .module)
        case .timeout: return String(localized: "El servidor tardó demasiado en responder", bundle: .module)
        case let .http(status): return String(localized: "Código HTTP \(status)", bundle: .module)
        case let .transport(message): return message
        }
    }
}

public struct HTTPResponse: Sendable {
    public var data: Data
    public var url: URL
    public var status: Int
    public var textEncodingName: String?

    /// Body decoded with the charset the server declares (the OPAC sends ISO-8859-1), like httpx `.text`.
    public var text: String {
        if let name = textEncodingName {
            let cf = CFStringConvertIANACharSetNameToEncoding(name as CFString)
            if cf != kCFStringEncodingInvalidId,
               let s = String(data: data, encoding: String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))) {
                return s
            }
        }
        return String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    }
}

/// Thin URLSession wrapper: dedicated configuration, per-client cookie jar, timeouts, GET retries.
public final class HTTPClient: @unchecked Sendable {
    public static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36"

    public struct Options: Sendable {
        public var timeout: TimeInterval
        public var headers: [String: String]
        /// Extra attempts for GET requests on transient failures (timeouts, dropped connections, 502/503/504).
        public var getRetries: Int
        public var retryDelay: TimeInterval
        /// Test hook: `URLProtocol` classes injected into the session configuration.
        public var protocolClasses: [AnyClass]

        public init(timeout: TimeInterval, headers: [String: String], getRetries: Int = 1,
                    retryDelay: TimeInterval = 0.6, protocolClasses: [AnyClass] = []) {
            self.timeout = timeout
            self.headers = headers
            self.getRetries = getRetries
            self.retryDelay = retryDelay
            self.protocolClasses = protocolClasses
        }
    }

    public let session: URLSession
    private let options: Options

    /// Each client owns an isolated in-memory cookie jar (ephemeral configuration), like a Python
    /// `httpx.AsyncClient`: cookies persist across the requests of one OPAC session and nowhere else.
    public init(options: Options) {
        self.options = options
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = options.timeout
        config.timeoutIntervalForResource = options.timeout * 3
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpAdditionalHeaders = options.headers
        if !options.protocolClasses.isEmpty {
            config.protocolClasses = options.protocolClasses + (config.protocolClasses ?? [])
        }
        session = URLSession(configuration: config)
    }

    deinit { session.finishTasksAndInvalidate() }

    public func get(_ url: URL) async throws -> HTTPResponse {
        var attempt = 0
        while true {
            do {
                let response = try await send(URLRequest(url: url))
                if [502, 503, 504].contains(response.status), attempt < options.getRetries {
                    attempt += 1
                    try await Task.sleep(nanoseconds: UInt64(options.retryDelay * 1e9))
                    continue
                }
                return response
            } catch let error as NetworkError where attempt < options.getRetries && error.isTransient {
                attempt += 1
                try await Task.sleep(nanoseconds: UInt64(options.retryDelay * 1e9))
            }
        }
    }

    /// `application/x-www-form-urlencoded` POST, encoded exactly like httpx `data=` (UTF-8, `+` for spaces).
    public func postForm(_ url: URL, fields: [(String, String)]) async throws -> HTTPResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(Self.formEncode(fields).utf8)
        return try await send(request)
    }

    /// Python `urllib.parse.urlencode` (quote_plus): keep `A-Za-z0-9_.-~`, space → `+`, rest %XX of UTF-8.
    public static func formEncode(_ fields: [(String, String)]) -> String {
        func quote(_ s: String) -> String {
            var out = ""
            for byte in s.utf8 {
                switch byte {
                case UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "A")...UInt8(ascii: "Z"),
                     UInt8(ascii: "0")...UInt8(ascii: "9"), UInt8(ascii: "_"), UInt8(ascii: "."),
                     UInt8(ascii: "-"), UInt8(ascii: "~"):
                    out.append(Character(Unicode.Scalar(byte)))
                case UInt8(ascii: " "):
                    out.append("+")
                default:
                    out += String(format: "%%%02X", byte)
                }
            }
            return out
        }
        return fields.map { "\(quote($0.0))=\(quote($0.1))" }.joined(separator: "&")
    }

    private func send(_ request: URLRequest) async throws -> HTTPResponse {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw NetworkError.transport("Respuesta no HTTP") }
            return HTTPResponse(data: data, url: http.url ?? request.url!, status: http.statusCode,
                                textEncodingName: http.textEncodingName)
        } catch let error as NetworkError {
            throw error
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff:
                throw NetworkError.offline
            case .timedOut:
                throw NetworkError.timeout
            case .cancelled:
                throw CancellationError()
            default:
                throw NetworkError.transport(error.localizedDescription)
            }
        }
    }
}

extension NetworkError {
    var isTransient: Bool {
        switch self {
        case .timeout, .transport: return true
        case .offline, .http: return false
        }
    }
}
