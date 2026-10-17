import Foundation

public struct CredentialStore: Sendable {
    private struct Credentials: Codable {
        var username: String
        var password: String
    }

    private let keychain: Keychain
    private let account: String

    public init(keychain: Keychain = Keychain(), account: String = "credentials") {
        self.keychain = keychain
        self.account = account
    }

    public func save(username: String, password: String) {
        let credentials = Credentials(username: username, password: password)
        guard let data = try? JSONEncoder().encode(credentials) else { return }
        _ = keychain.set(data, for: account)
    }

    public func load() -> (username: String, password: String)? {
        guard let data = keychain.data(for: account),
              let credentials = try? JSONDecoder().decode(Credentials.self, from: data) else {
            return nil
        }
        return (credentials.username, credentials.password)
    }

    public func clear() {
        _ = keychain.remove(account: account)
    }
}
