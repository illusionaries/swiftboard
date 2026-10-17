import Foundation

/// One recording in a course's replay list. `playURL` contains a short-lived
/// signed token and must never be logged or persisted.
public struct CourseVideo: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let time: String
    public let teacher: String
    public let playURL: URL

    public init(id: String, title: String, time: String, teacher: String, playURL: URL) {
        self.id = id
        self.title = title
        self.time = time
        self.teacher = teacher
        self.playURL = playURL
    }
}

/// A rewritten, playable HLS manifest. Encryption keys are fetched with the
/// signed-in PKU session and served to AVPlayer through a resource loader.
public struct PreparedVideo: Sendable {
    public let title: String
    public let teacher: String?
    public let duration: Double?
    public let playlist: String
    public let keys: [Data]

    public init(title: String, teacher: String?, duration: Double?, playlist: String, keys: [Data]) {
        self.title = title
        self.teacher = teacher
        self.duration = duration
        self.playlist = playlist
        self.keys = keys
    }
}

public enum VideoError: Error, LocalizedError, Sendable {
    case unavailable
    case authFailed
    case noRecording
    case invalidPlaylist
    case keyUnauthorized
    case keyUnavailable
    case server(String)

    public var errorDescription: String? {
        switch self {
        case .unavailable: "暂时无法读取课程回放"
        case .authFailed: "回放凭证已失效，请返回重试"
        case .noRecording: "这节课还没有可播放的回放"
        case .invalidPlaylist: "回放格式无法识别"
        case .keyUnauthorized: "回放密钥已过期，请重新登录后重试"
        case .keyUnavailable: "无法获取回放密钥"
        case .server(let message): message
        }
    }
}

public struct CourseVideoService: Sendable {
    private let http: HTTPClient

    public init(http: HTTPClient) {
        self.http = http
    }

    private static let listPath = "/webapps/bb-streammedia-hqy-BBLEARN/videoList.action"
    private static let listBase = "/webapps/bb-streammedia-hqy-BBLEARN/"

    // MARK: - List

    public func list(courseID: String) async throws -> [CourseVideo] {
        var components = URLComponents(url: BlackboardClient.baseURL, resolvingAgainstBaseURL: false)!
        components.path = Self.listPath
        components.queryItems = [
            URLQueryItem(name: "sortDir", value: "ASCENDING"),
            URLQueryItem(name: "numResults", value: "100"),
            URLQueryItem(name: "editPaging", value: "false"),
            URLQueryItem(name: "course_id", value: courseID),
            URLQueryItem(name: "mode", value: "view"),
            URLQueryItem(name: "startIndex", value: "0")
        ]
        var request = HTTPRequest(url: components.url!)
        request.headers["Accept"] = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
        let response = try await http.send(request)

        if response.url.path.contains("/webapps/login") {
            throw APIError.notAuthenticated
        }
        guard response.isSuccess else {
            throw VideoError.server("无法读取回放列表（HTTP \(response.status)）")
        }
        let html = response.text
        if html.contains("loginForm") && !html.contains("listContainer_databody") {
            throw APIError.notAuthenticated
        }
        guard let tbody = html.videoFirstMatch(
            #"<tbody[^>]*id\s*=\s*["']listContainer_databody["'][^>]*>(.*?)</tbody>"#
        ), tbody.count > 1 else {
            return []
        }

        let listURL = response.url
        var videos: [CourseVideo] = []
        var seen = Set<String>()
        for row in tbody[1].videoAllMatches(#"<tr\b[^>]*>(.*?)</tr>"#) {
            guard row.count > 1 else { continue }
            let rowHTML = row[1]

            let title = rowHTML.videoFirstMatch(#"<th\b[^>]*>(.*?)</th>"#)
                .flatMap { $0.count > 1 ? $0[1].htmlToPlainText : nil } ?? ""
            let values = rowHTML.videoAllMatches(
                #"<span[^>]*class\s*=\s*["'][^"']*table-data-cell-value[^"']*["'][^>]*>(.*?)</span>"#
            ).compactMap { $0.count > 1 ? $0[1].htmlToPlainText : nil }

            let time = values.first ?? ""
            let teacher = values.count > 1 ? values[1] : ""
            guard let link = rowHTML.videoFirstMatch(
                #"href\s*=\s*["']([^"']*playVideo\.action\?token=[^"']+)["']"#
            ).flatMap({ $0.count > 1 ? $0[1] : nil }),
            let playURL = URL(string: link, relativeTo: listURL)?.absoluteURL else {
                continue
            }

            let identifier = "\(courseID)|\(time)|\(title)"
            guard seen.insert(identifier).inserted else { continue }
            videos.append(
                CourseVideo(
                    id: identifier,
                    title: title.isEmpty ? (time.isEmpty ? "课程回放" : time) : title,
                    time: time,
                    teacher: teacher,
                    playURL: playURL
                )
            )
        }
        return videos
    }

    // MARK: - Prepare

    public func prepare(video: CourseVideo) async throws -> PreparedVideo {
        let playPage = try await http.send(HTTPRequest(url: video.playURL, timeout: 60))
        if playPage.url.path.contains("/webapps/login") {
            throw APIError.notAuthenticated
        }
        guard playPage.isSuccess else {
            throw VideoError.server("无法打开回放（HTTP \(playPage.status)）")
        }
        let playHTML = playPage.text
        guard let iframeMatch = playHTML.videoFirstMatch(
            #"<iframe[^>]*\bsrc\s*=\s*["']([^"']*yjapise[^"']*)["']"#
        ), iframeMatch.count > 1 else {
            throw VideoError.unavailable
        }
        let iframeString = iframeMatch[1]
            .replacingOccurrences(of: "&amp;", with: "&")
        guard let iframeURL = URL(string: iframeString),
              iframeURL.scheme == "https",
              isPKUHost(iframeURL.host) else {
            throw VideoError.authFailed
        }

        // Following the CAS redirect also installs the video platform's
        // `.pku.edu.cn` cookies (`_token`), which are required by the key URL.
        let casResponse = try await http.send(HTTPRequest(url: iframeURL, timeout: 60))
        guard let playerURL = Optional(casResponse.url),
              let playerComponents = URLComponents(url: playerURL, resolvingAgainstBaseURL: false),
              isPKUHost(playerURL.host) else {
            throw VideoError.authFailed
        }
        var query: [String: String] = [:]
        for item in playerComponents.queryItems ?? [] {
            if let value = item.value {
                query[item.name] = value
            }
        }
        guard let courseID = query["course_id"],
              let subID = query["sub_id"],
              let appID = query["app_id"],
              let authData = query["auth_data"] else {
            throw VideoError.authFailed
        }

        var apiComponents = URLComponents(string: "https://yjapise.pku.edu.cn/courseapi/v2/schedule/get-sub-info-by-auth-data")!
        apiComponents.queryItems = [
            URLQueryItem(name: "all", value: "1"),
            URLQueryItem(name: "course_id", value: courseID),
            URLQueryItem(name: "sub_id", value: subID),
            URLQueryItem(name: "with_sub_data", value: "1"),
            URLQueryItem(name: "app_id", value: appID),
            URLQueryItem(name: "auth_data", value: authData)
        ]
        var apiRequest = HTTPRequest(url: apiComponents.url!, timeout: 60)
        apiRequest.headers["Accept"] = "application/json"
        apiRequest.headers["Referer"] = "https://onlineroomse.pku.edu.cn/"
        let apiResponse = try await http.send(apiRequest)
        guard apiResponse.isSuccess else {
            throw VideoError.server("无法读取回放信息（HTTP \(apiResponse.status)）")
        }
        let subInfo: SubInfoResponse
        do {
            subInfo = try JSONDecoder().decode(SubInfoResponse.self, from: apiResponse.data)
        } catch {
            throw VideoError.invalidPlaylist
        }
        if let code = subInfo.code, code != 0 {
            throw VideoError.server(subInfo.msg?.isEmpty == false ? subInfo.msg! : "无法读取回放信息")
        }
        guard let item = subInfo.list?.first,
              let contentString = item.subContent,
              let subContent = try? JSONDecoder().decode(SubContent.self, from: Data(contentString.utf8)),
              let playback = subContent.savePlayback,
              playback.isM3U8 == "yes",
              let m3u8String = playback.contents,
              let m3u8URL = URL(string: m3u8String),
              m3u8URL.scheme == "https" else {
            throw VideoError.noRecording
        }

        let media = try await mediaPlaylist(url: m3u8URL, depth: 0)
        let rewritten = try await rewritePlaylist(url: media.url, text: media.text)

        return PreparedVideo(
            title: (item.subTitle?.isEmpty == false ? item.subTitle! : video.title),
            teacher: item.lecturerName ?? video.teacher,
            duration: Double(item.subDuration ?? ""),
            playlist: rewritten.playlist,
            keys: rewritten.keys
        )
    }

    private func isPKUHost(_ host: String?) -> Bool {
        guard let host else { return false }
        return host == "pku.edu.cn" || host.hasSuffix(".pku.edu.cn")
    }

    // MARK: - Playlist

    private struct MediaPlaylist {
        let url: URL
        let text: String
    }

    private func mediaPlaylist(url: URL, depth: Int) async throws -> MediaPlaylist {
        guard depth < 3 else { throw VideoError.invalidPlaylist }
        var request = HTTPRequest(url: url, timeout: 60)
        request.headers["Accept"] = "application/vnd.apple.mpegurl,application/x-mpegURL,*/*"
        let response = try await http.send(request)
        guard response.isSuccess else {
            throw VideoError.server("无法读取回放列表（HTTP \(response.status)）")
        }
        let text = response.text
        guard text.contains("#EXTM3U") else { throw VideoError.invalidPlaylist }

        if text.contains("#EXT-X-STREAM-INF") {
            var best: (bandwidth: Int, uri: String)?
            var pendingBandwidth: Int?
            for rawLine in text.components(separatedBy: .newlines) {
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                if line.hasPrefix("#EXT-X-STREAM-INF") {
                    if let match = line.videoFirstMatch(#"(?i)BANDWIDTH=(\d+)"#),
                       match.count > 1 {
                        pendingBandwidth = Int(match[1])
                    }
                } else if !line.isEmpty, !line.hasPrefix("#"), let bandwidth = pendingBandwidth {
                    if best == nil || bandwidth > best!.bandwidth {
                        best = (bandwidth, line)
                    }
                    pendingBandwidth = nil
                }
            }
            guard let best,
                  let variant = URL(string: best.uri, relativeTo: url)?.absoluteURL else {
                throw VideoError.invalidPlaylist
            }
            return try await mediaPlaylist(url: variant, depth: depth + 1)
        }
        return MediaPlaylist(url: response.url, text: text)
    }

    private struct Rewritten {
        let playlist: String
        let keys: [Data]
    }

    private func rewritePlaylist(url: URL, text: String) async throws -> Rewritten {
        var keys: [Data] = []
        var keyIndices: [String: Int] = [:]
        var output: [String] = []

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#EXT-X-KEY") {
                if line.uppercased().contains("METHOD=NONE") {
                    output.append(rawLine)
                    continue
                }
                guard let match = line.videoFirstMatch(#"(?i)URI="([^"]*)""#),
                      match.count > 1,
                      let keyURL = URL(string: match[1], relativeTo: url)?.absoluteURL else {
                    throw VideoError.keyUnavailable
                }
                let index: Int
                if let existing = keyIndices[keyURL.absoluteString] {
                    index = existing
                } else {
                    let fetched = try await fetchKey(keyURL)
                    index = keys.count
                    keys.append(fetched)
                    keyIndices[keyURL.absoluteString] = index
                }
                let replaced = rawLine.replacingOccurrences(
                    of: "URI=\"\(match[1])\"",
                    with: "URI=\"swiftboard-key://key/\(index)\""
                )
                output.append(replaced)
            } else if line.hasPrefix("#EXT-X-MAP") {
                if let match = line.videoFirstMatch(#"(?i)URI="([^"]*)""#),
                   match.count > 1,
                   let mapURL = URL(string: match[1], relativeTo: url)?.absoluteURL {
                    output.append(
                        rawLine.replacingOccurrences(
                            of: "URI=\"\(match[1])\"",
                            with: "URI=\"\(mapURL.absoluteString)\""
                        )
                    )
                } else {
                    output.append(rawLine)
                }
            } else if !line.isEmpty, !line.hasPrefix("#") {
                if let segmentURL = URL(string: line, relativeTo: url)?.absoluteURL {
                    output.append(segmentURL.absoluteString)
                } else {
                    output.append(rawLine)
                }
            } else {
                output.append(rawLine)
            }
        }

        return Rewritten(playlist: output.joined(separator: "\n"), keys: keys)
    }

    private func fetchKey(_ url: URL) async throws -> Data {
        var request = HTTPRequest(url: url, timeout: 30, throwsOnUnauthorized: false)
        request.headers["Accept"] = "*/*"
        let response = try await http.send(request)
        if response.status == 401 {
            throw VideoError.keyUnauthorized
        }
        guard response.isSuccess, response.data.count == 16 else {
            throw VideoError.keyUnavailable
        }
        return response.data
    }
}

private struct SubInfoResponse: Decodable {
    let code: Int?
    let msg: String?
    let list: [SubInfoItem]?
}

private struct SubInfoItem: Decodable {
    let subTitle: String?
    let subDuration: String?
    let subContent: String?
    let lecturerName: String?
    let roomName: String?

    enum CodingKeys: String, CodingKey {
        case subTitle = "sub_title"
        case subDuration = "sub_duration"
        case subContent = "sub_content"
        case lecturerName = "lecturer_name"
        case roomName = "room_name"
    }
}

private struct SubContent: Decodable {
    let savePlayback: SavePlayback?

    enum CodingKeys: String, CodingKey {
        case savePlayback = "save_playback"
    }
}

private struct SavePlayback: Decodable {
    let contents: String?
    let isM3U8: String?
    let contentsDuration: String?

    enum CodingKeys: String, CodingKey {
        case contents
        case isM3U8 = "is_m3u8"
        case contentsDuration = "contents_duration"
    }
}

private extension String {
    func videoFirstMatch(_ pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return nil }
        let range = NSRange(startIndex..<endIndex, in: self)
        guard let match = regex.firstMatch(in: self, range: range) else { return nil }
        return (0..<match.numberOfRanges).map { index in
            guard let range = Range(match.range(at: index), in: self) else { return "" }
            return String(self[range])
        }
    }

    func videoAllMatches(_ pattern: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return [] }
        let range = NSRange(startIndex..<endIndex, in: self)
        return regex.matches(in: self, range: range).map { match in
            (0..<match.numberOfRanges).map { index in
                guard let range = Range(match.range(at: index), in: self) else { return "" }
                return String(self[range])
            }
        }
    }
}

extension BlackboardClient {
    public var videos: CourseVideoService { CourseVideoService(http: http) }
}
