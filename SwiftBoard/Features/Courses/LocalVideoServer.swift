import Foundation
import Network
import SwiftBoardKit

/// Tiny loopback HTTP server that serves the rewritten HLS playlist and its
/// AES-128 keys to AVPlayer. AVPlayer needs an http(s) URL to recognise HLS;
/// the playlist and key never leave the device.
final class LocalVideoServer: @unchecked Sendable {
    private let keys: [Data]
    private let segmentsDirectory: URL?
    private let queue = DispatchQueue(label: "SwiftBoard.LocalVideoServer")
    private var listener: NWListener?
    private var playlist: Data?
    private(set) var port: UInt16 = 0

    init(keys: [Data], segmentsDirectory: URL? = nil) {
        self.keys = keys
        self.segmentsDirectory = segmentsDirectory
    }

    func setPlaylist(_ playlist: String) {
        self.playlist = Data(playlist.utf8)
    }

    func start() async throws -> UInt16 {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        let listener = try NWListener(using: parameters)
        self.listener = listener

        return try await withCheckedThrowingContinuation { continuation in
            let box = ContinuationBox(continuation)
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if let port = listener.port?.rawValue {
                        box.resume(.success(port))
                    } else {
                        box.resume(.failure(VideoError.server("本地回放服务启动失败")))
                    }
                case .failed(let error):
                    box.resume(.failure(error))
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            listener.start(queue: queue)
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, _, error in
            guard let self, error == nil, let data, !data.isEmpty else {
                connection.cancel()
                return
            }
            let request = String(decoding: data, as: UTF8.self)
            let firstLine = request.components(separatedBy: "\r\n").first ?? ""
            let parts = firstLine.split(separator: " ")
            let method = parts.first.map(String.init) ?? "GET"
            let rawPath = parts.count > 1 ? String(parts[1]) : "/"
            let path = rawPath.components(separatedBy: "?").first ?? rawPath
            var headers: [String: String] = [:]
            for line in request.components(separatedBy: "\r\n").dropFirst() {
                guard let colon = line.firstIndex(of: ":") else { continue }
                let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
                let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                headers[name] = value
            }

            let response = self.response(method: method, path: path, headers: headers)
            connection.send(content: response, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }

    private func response(method: String, path: String, headers: [String: String]) -> Data {
        guard method == "GET" || method == "HEAD" else {
            return httpResponse(status: "405 Method Not Allowed", contentType: "text/plain", body: Data())
        }
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        if path == "/playlist.m3u8" {
            guard let playlist else {
                return httpResponse(status: "404 Not Found", contentType: "text/plain", body: Data())
            }
            return httpResponse(
                status: "200 OK",
                contentType: "application/vnd.apple.mpegurl",
                body: method == "HEAD" ? Data() : playlist,
                contentLength: playlist.count
            )
        }
        if let segmentsDirectory, path.hasPrefix("/segment_") {
            let name = String(path.dropFirst())
            guard !name.contains("/"), !name.contains(".."), !name.isEmpty else {
                return httpResponse(status: "404 Not Found", contentType: "text/plain", body: Data())
            }
            return segmentResponse(
                name: name,
                method: method,
                headers: headers,
                directory: segmentsDirectory
            )
        }
        guard components.count == 2, components[0] == "key", let index = Int(components[1]),
              keys.indices.contains(index) else {
            return httpResponse(status: "404 Not Found", contentType: "text/plain", body: Data())
        }
        let body = keys[index]
        return httpResponse(
            status: "200 OK",
            contentType: "application/octet-stream",
            body: method == "HEAD" ? Data() : body,
            contentLength: body.count
        )
    }

    private func segmentResponse(
        name: String,
        method: String,
        headers: [String: String],
        directory: URL
    ) -> Data {
        let fileURL = directory.appendingPathComponent(name)
        guard let data = try? Data(contentsOf: fileURL), !data.isEmpty else {
            return httpResponse(status: "404 Not Found", contentType: "text/plain", body: Data())
        }

        var start = 0
        var end = data.count - 1
        var partial = false
        if let range = headers["range"], range.hasPrefix("bytes=") {
            let spec = range.dropFirst("bytes=".count).split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
            if let first = spec.first, !first.isEmpty, let requestedStart = Int(first) {
                start = max(0, requestedStart)
            }
            if spec.count > 1, !spec[1].isEmpty, let requestedEnd = Int(spec[1]) {
                end = min(data.count - 1, requestedEnd)
            }
            guard start <= end, start < data.count else {
                return httpResponse(
                    status: "416 Range Not Satisfiable",
                    contentType: "text/plain",
                    body: Data(),
                    extraHeaders: ["Content-Range": "bytes */\(data.count)"]
                )
            }
            partial = true
        }

        let slice = data.subdata(in: start..<(end + 1))
        var extra: [String: String] = [:]
        if partial {
            extra["Content-Range"] = "bytes \(start)-\(end)/\(data.count)"
        }
        return httpResponse(
            status: partial ? "206 Partial Content" : "200 OK",
            contentType: "video/mp2t",
            body: method == "HEAD" ? Data() : slice,
            contentLength: slice.count,
            extraHeaders: extra,
            acceptRanges: true
        )
    }

    private func httpResponse(
        status: String,
        contentType: String,
        body: Data,
        contentLength: Int? = nil,
        extraHeaders: [String: String] = [:],
        acceptRanges: Bool = false
    ) -> Data {
        let length = contentLength ?? body.count
        var header = "HTTP/1.1 \(status)\r\n"
        header += "Content-Type: \(contentType)\r\n"
        header += "Content-Length: \(length)\r\n"
        header += "Accept-Ranges: \(acceptRanges ? "bytes" : "none")\r\n"
        for (name, value) in extraHeaders {
            header += "\(name): \(value)\r\n"
        }
        header += "Cache-Control: no-store\r\n"
        header += "Connection: close\r\n\r\n"
        var data = Data(header.utf8)
        data.append(body)
        return data
    }
}


private final class ContinuationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<UInt16, Error>?

    init(_ continuation: CheckedContinuation<UInt16, Error>) {
        self.continuation = continuation
    }

    func resume(_ result: Result<UInt16, Error>) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }
}
