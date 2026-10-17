import Foundation

/// High-level entry point used by the app and the `bbprobe` CLI.
public struct PKUClient: Sendable {
    public let http: HTTPClient
    public let blackboard: BlackboardClient
    public let credentials: CredentialStore
    private let iaaa: IAAAClient

    public init(persistCookies: Bool = true) {
        let http = HTTPClient(persistCookies: persistCookies)
        self.http = http
        self.blackboard = BlackboardClient(http: http)
        self.iaaa = IAAAClient(http: http)
        self.credentials = CredentialStore()
    }

    /// Signs in through IAAA and establishes the Blackboard session.
    public func signIn(
        username: String,
        password: String,
        otpCode: String = "",
        smsCode: String = "",
        randCode: String = ""
    ) async throws -> UserProfile {
        let token = try await iaaa.authenticate(
            username: username,
            password: password,
            otpCode: otpCode,
            smsCode: smsCode,
            randCode: randCode
        )
        try await blackboard.campusLogin(token: token)

        var lastError: Error = APIError.notAuthenticated
        for attempt in 0..<3 {
            do {
                return try await blackboard.profile()
            } catch {
                lastError = error
                if attempt < 2 { try? await Task.sleep(for: .milliseconds(400)) }
            }
        }
        throw lastError
    }

    /// Restores the saved cookies and validates them against the API.
    public func restoreSession() async -> UserProfile? {
        guard await CookieVault.shared.restore() > 0 else { return nil }
        return try? await blackboard.profile()
    }

    public func signOut() async {
        if let cookies = HTTPCookieStorage.shared.cookies {
            for cookie in cookies where cookie.domain.hasSuffix("pku.edu.cn") {
                HTTPCookieStorage.shared.deleteCookie(cookie)
            }
        }
        await CookieVault.shared.clear()
    }

    public func saveCredentials(username: String, password: String) {
        credentials.save(username: username, password: password)
    }
}
