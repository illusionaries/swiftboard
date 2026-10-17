import Foundation

/// Persists the Blackboard/IAAA cookies so that relaunching the app does not
/// require a fresh login. URLSession keeps persistent cookies on disk itself,
/// but Blackboard's session cookies (`JSESSIONID`, `s_session_id`) are
/// session-only, so we keep a snapshot in the keychain as well.
public actor CookieVault {
    public static let shared = CookieVault()

    private struct StoredCookie: Codable {
        var name: String
        var value: String
        var domain: String
        var path: String
        var expires: Date?
        var secure: Bool
        var httpOnly: Bool
    }

    private let keychain: Keychain
    private let account: String
    private var lastFingerprint: Int = 0

    public init(keychain: Keychain = Keychain(), account: String = "blackboard-cookies") {
        self.keychain = keychain
        self.account = account
    }

    /// Encodes and stores the currently known PKU cookies. Calls are coalesced
    /// because a single login can produce a series of `Set-Cookie` headers.
    public func capture(_ cookies: [HTTPCookie]) {
        let relevant = cookies.filter { isPKUCookie($0) }
        let fingerprint = relevant.reduce(into: 0) { partial, cookie in
            partial = partial &+ cookie.name.hashValue &+ cookie.value.hashValue
        }
        guard fingerprint != lastFingerprint else { return }
        lastFingerprint = fingerprint

        let stored = relevant.map {
            StoredCookie(
                name: $0.name,
                value: $0.value,
                domain: $0.domain,
                path: $0.path,
                expires: $0.expiresDate,
                secure: $0.isSecure,
                httpOnly: $0.isHTTPOnly
            )
        }
        guard let data = try? JSONEncoder().encode(stored) else { return }
        _ = keychain.set(data, for: account)
    }

    /// Restores the saved cookies into URLSession's shared cookie storage.
    /// Returns the number of cookies that were restored.
    @discardableResult
    public func restore() -> Int {
        guard let data = keychain.data(for: account),
              let stored = try? JSONDecoder().decode([StoredCookie].self, from: data) else {
            return 0
        }
        var restored = 0
        let now = Date()
        for cookie in stored {
            if let expires = cookie.expires, expires < now { continue }
            var properties: [HTTPCookiePropertyKey: Any] = [
                .name: cookie.name,
                .value: cookie.value,
                .domain: cookie.domain,
                .path: cookie.path,
                .version: 0
            ]
            if let expires = cookie.expires { properties[.expires] = expires }
            if cookie.secure { properties[.secure] = "TRUE" }
            if cookie.httpOnly { properties[.init("HttpOnly")] = "TRUE" }
            if let httpCookie = HTTPCookie(properties: properties) {
                HTTPCookieStorage.shared.setCookie(httpCookie)
                restored += 1
            }
        }
        lastFingerprint = stored.reduce(into: 0) { partial, cookie in
            partial = partial &+ cookie.name.hashValue &+ cookie.value.hashValue
        }
        return restored
    }

    public func clear() {
        lastFingerprint = 0
        _ = keychain.remove(account: account)
    }

    private func isPKUCookie(_ cookie: HTTPCookie) -> Bool {
        cookie.domain.hasSuffix("pku.edu.cn")
    }
}
