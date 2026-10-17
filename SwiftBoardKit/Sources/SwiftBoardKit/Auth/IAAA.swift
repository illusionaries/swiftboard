import Foundation

/// Sign-in against Peking University's unified authentication service (IAAA).
///
/// The flow mirrors the browser:
/// 1. fetch an RSA public key,
/// 2. encrypt the password with PKCS#1 v1.5,
/// 3. exchange it for a short-lived token,
/// 4. hand the token to Blackboard's campus-login endpoint.
public struct IAAAClient: Sendable {
    public static let campusLoginURL = "http://course.pku.edu.cn/webapps/bb-sso-BBLEARN/execute/authValidate/campusLogin"
    public static let oauthPage = "https://iaaa.pku.edu.cn/iaaa/oauth.jsp"

    private let http: HTTPClient
    private let base = URL(string: "https://iaaa.pku.edu.cn")!

    public init(http: HTTPClient) {
        self.http = http
    }

    /// Returns the one-time token that Blackboard's campusLogin endpoint needs.
    public func authenticate(
        username: String,
        password: String,
        otpCode: String = "",
        smsCode: String = "",
        randCode: String = ""
    ) async throws -> String {
        let trimmedUser = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUser.isEmpty, !password.isEmpty else {
            throw APIError.login(message: "请输入学号和密码", code: nil)
        }

        // Prime the IAAA session cookie.
        var oauthComponents = URLComponents(string: Self.oauthPage)!
        oauthComponents.queryItems = [
            URLQueryItem(name: "appID", value: "blackboard"),
            URLQueryItem(name: "appName", value: "1"),
            URLQueryItem(name: "redirectUrl", value: Self.campusLoginURL)
        ]
        let oauthURL = oauthComponents.url!
        _ = try? await http.send(HTTPRequest(url: oauthURL))

        let keyResponse = try await http.send(
            HTTPRequest(
                url: base.appendingPathComponent("/iaaa/getPublicKey.do"),
                headers: ["X-Requested-With": "XMLHttpRequest"]
            )
        )
        guard keyResponse.isSuccess else {
            throw APIError.http(status: keyResponse.status, message: "无法获取登录公钥")
        }
        guard let key = try? JSONDecoder().decode(IAAAPublicKeyDTO.self, from: keyResponse.data),
              key.success else {
            throw APIError.invalidResponse("登录公钥")
        }

        let encryptedPassword: String
        do {
            encryptedPassword = try RSA.encrypt(password, publicKeyPEM: key.key)
        } catch {
            throw APIError.login(message: error.localizedDescription, code: nil)
        }

        let loginRequest = HTTPRequest.form(
            url: base.appendingPathComponent("/iaaa/oauthlogin.do"),
            fields: [
                ("appid", "blackboard"),
                ("userName", trimmedUser),
                ("password", encryptedPassword),
                ("randCode", randCode),
                ("smsCode", smsCode),
                ("otpCode", otpCode),
                ("remTrustChk", "false"),
                ("redirUrl", Self.campusLoginURL)
            ],
            headers: [
                "Referer": oauthURL.absoluteString,
                "Origin": "https://iaaa.pku.edu.cn"
            ]
        )
        let response = try await http.send(loginRequest)
        guard response.isSuccess else {
            throw APIError.http(status: response.status, message: "统一身份认证暂时不可用")
        }
        guard let result = try? JSONDecoder().decode(IAAALoginDTO.self, from: response.data) else {
            throw APIError.invalidResponse("统一身份认证返回了无法识别的数据")
        }

        if result.success, let token = result.token {
            return token
        }

        let code = result.errors?.code
        let message = result.errors?.msg ?? "登录失败，请检查学号和密码"
        throw APIError.login(message: Self.friendlyMessage(code: code, serverMessage: message), code: code)
    }

    static func friendlyMessage(code: String?, serverMessage: String) -> String {
        switch code {
        case "E21": return "登录尝试过于频繁，请半小时后再试"
        case "E02": return "账号尚未激活，请先在 IAAA 激活账号"
        case "E03": return "需要输入图形验证码"
        case "E04": return "需要短信验证码，请前往网页登录"
        case "E05": return "需要手机令牌验证码"
        case "E01": return "学号或密码错误"
        default: return serverMessage.isEmpty ? "登录失败" : serverMessage
        }
    }
}
