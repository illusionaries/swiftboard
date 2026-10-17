import Foundation

public enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
}

public struct HTTPRequest: Sendable {
    public var url: URL
    public var method: HTTPMethod
    public var headers: [String: String]
    public var body: Data?
    public var contentType: String?
    public var timeout: TimeInterval

    public init(
        url: URL,
        method: HTTPMethod = .get,
        headers: [String: String] = [:],
        body: Data? = nil,
        contentType: String? = nil,
        timeout: TimeInterval = 30
    ) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
        self.contentType = contentType
        self.timeout = timeout
    }

    /// Builds an `application/x-www-form-urlencoded` POST request.
    public static func form(
        url: URL,
        fields: [(String, String)],
        headers: [String: String] = [:],
        timeout: TimeInterval = 30
    ) -> HTTPRequest {
        var request = HTTPRequest(
            url: url,
            method: .post,
            headers: headers,
            body: FormEncoder.encode(fields),
            contentType: "application/x-www-form-urlencoded; charset=UTF-8",
            timeout: timeout
        )
        request.headers["Accept"] = "application/json, text/javascript, */*; q=0.01"
        request.headers["X-Requested-With"] = "XMLHttpRequest"
        return request
    }
}

public struct HTTPResponse: Sendable {
    public let data: Data
    public let status: Int
    public let headers: [String: String]
    public let url: URL

    public var text: String { String(data: data, encoding: .utf8) ?? "" }

    public var isSuccess: Bool { (200..<300).contains(status) }

    public var contentType: String { headers["content-type"] ?? "" }

    public var isHTML: Bool { contentType.contains("text/html") }

    public func header(_ name: String) -> String? {
        headers[name.lowercased()]
    }
}

public enum APIError: Error, LocalizedError, Sendable {
    case notAuthenticated
    case http(status: Int, message: String?)
    case invalidResponse(String)
    case decoding(String)
    case network(String)
    case login(message: String, code: String?)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            "登录状态已失效，请重新登录"
        case .http(let status, let message):
            message ?? "服务器返回了错误（HTTP \(status)）"
        case .invalidResponse(let detail):
            "无法解析服务器响应：\(detail)"
        case .decoding(let detail):
            "数据格式异常：\(detail)"
        case .network(let detail):
            detail
        case .login(let message, _):
            message
        case .cancelled:
            "请求已取消"
        }
    }

    public var isCancellation: Bool {
        if case .cancelled = self { return true }
        return false
    }
}

enum FormEncoder {
    static func encode(_ fields: [(String, String)]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let string = fields.map { key, value in
            let encodedKey = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let encodedValue = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(encodedKey)=\(encodedValue)"
        }.joined(separator: "&")
        return Data(string.utf8)
    }
}

private final class DownloadProgressDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let onProgress: @Sendable (Double) -> Void

    init(onProgress: @escaping @Sendable (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress(min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
    }
}

/// Networking facade. Cookies are handled by URLSession's shared cookie
/// storage, which deals with path scoping and redirects for us.
public struct HTTPClient: Sendable {
    public static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Safari/605.1.15"

    public let session: URLSession
    public let cookieVault: CookieVault?

    public init(persistCookies: Bool = true) {
        let configuration: URLSessionConfiguration = persistCookies
            ? URLSessionConfiguration.default
            : URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 300
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpAdditionalHeaders = [
            "User-Agent": Self.userAgent,
            "Accept-Language": "zh-CN,zh-Hans;q=0.9,en;q=0.8"
        ]
        configuration.httpShouldSetCookies = true
        configuration.httpCookieAcceptPolicy = .always
        if persistCookies {
            configuration.httpCookieStorage = .shared
            cookieVault = .shared
        } else {
            cookieVault = nil
        }
        session = URLSession(configuration: configuration)
    }

    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.timeoutInterval = request.timeout
        for (key, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }
        if let contentType = request.contentType {
            urlRequest.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        urlRequest.httpBody = request.body

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch let error as URLError where error.code == .cancelled {
            throw APIError.cancelled
        } catch let error as URLError {
            throw APIError.network(Self.message(for: error))
        } catch {
            throw APIError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse("非 HTTP 响应")
        }

        if let cookieVault, let cookies = HTTPCookieStorage.shared.cookies {
            await cookieVault.capture(cookies)
        }

        var headers: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            headers[String(describing: key).lowercased()] = String(describing: value)
        }

        let result = HTTPResponse(
            data: data,
            status: http.statusCode,
            headers: headers,
            url: http.url ?? request.url
        )

        if result.status == 401 {
            throw APIError.notAuthenticated
        }
        return result
    }

    /// Downloads a file while reporting progress. The caller is responsible
    /// for the destination URL.
    public func download(
        _ url: URL,
        to destination: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        var request = URLRequest(url: url)
        request.timeoutInterval = 300
        let delegate = DownloadProgressDelegate(onProgress: progress)
        let temporaryURL: URL
        do {
            (temporaryURL, _) = try await session.download(for: request, delegate: delegate)
        } catch let error as URLError where error.code == .cancelled {
            throw APIError.cancelled
        } catch let error as URLError {
            throw APIError.network(Self.message(for: error))
        } catch {
            throw APIError.network(error.localizedDescription)
        }

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: temporaryURL, to: destination)
        progress(1)
    }

    static func message(for error: URLError) -> String {
        switch error.code {
        case .notConnectedToInternet: "网络未连接"
        case .timedOut: "连接超时，请稍后重试"
        case .cannotFindHost, .cannotConnectToHost: "无法连接到教学网，请检查网络"
        case .secureConnectionFailed: "安全连接失败"
        case .cancelled: "请求已取消"
        default: error.localizedDescription
        }
    }
}
