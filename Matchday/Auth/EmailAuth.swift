import Foundation

/// Email accounts with password reset, using Firebase Authentication's REST API (no SDK).
/// Firebase keeps the password (hashed) and Google sends the verification and reset emails.
/// The links open Google's own pages, so they work on any device: phone, tablet or computer.
/// Free (Spark) plan: 150 reset and 1,000 verification emails a day, no email server needed.
struct EmailAuth {
    let key = Secrets.firebaseAPIKey.trimmingCharacters(in: .whitespaces)

    var isConfigured: Bool { key.hasPrefix("AIza") }

    struct Session {
        let idToken: String
        let refreshToken: String
        let userID: String
        let email: String
        let username: String?
        var verified: Bool
    }

    // MARK: requests

    /// Creates the account, sets its username and emails a verification link.
    func signUp(email: String, password: String, username: String) async throws -> Session {
        let json = try await call("accounts:signUp", ["email": email, "password": password, "returnSecureToken": true])
        guard let s = Self.session(from: json) else { throw AuthError.emailFailed("No account came back.") }
        _ = try? await call("accounts:update", ["idToken": s.idToken, "displayName": username, "returnSecureToken": false])
        try await sendVerification(idToken: s.idToken)
        return Session(idToken: s.idToken, refreshToken: s.refreshToken, userID: s.userID, email: s.email, username: username, verified: false)
    }

    func signIn(email: String, password: String) async throws -> Session {
        let json = try await call("accounts:signInWithPassword", ["email": email, "password": password, "returnSecureToken": true])
        guard var s = Self.session(from: json) else { throw AuthError.emailFailed("No session came back.") }
        s.verified = try await isVerified(idToken: s.idToken)
        return s
    }

    func sendVerification(idToken: String) async throws {
        _ = try await call("accounts:sendOobCode", ["requestType": "VERIFY_EMAIL", "idToken": idToken])
    }

    func isVerified(idToken: String) async throws -> Bool {
        let json = try await call("accounts:lookup", ["idToken": idToken])
        let user = (json["users"] as? [[String: Any]])?.first
        return user?["emailVerified"] as? Bool ?? false
    }

    /// Emails a reset link. With email enumeration protection (on by default), Firebase answers
    /// the same whether or not the email has an account.
    func sendReset(email: String) async throws {
        _ = try await call("accounts:sendOobCode", ["requestType": "PASSWORD_RESET", "email": email])
    }

    /// Checks the saved refresh token is still good and returns the new one.
    /// Firebase revokes it after a password reset, so other devices get signed out.
    func refresh(_ token: String) async throws -> String { try await self.token(from: token).refreshToken }

    /// A short-lived ID token (for Firestore), its user id, and the rotated refresh token.
    struct Token { let idToken: String; let refreshToken: String; let userID: String }

    func token(from token: String) async throws -> Token {
        guard isConfigured else { throw AuthError.emailNotConfigured }
        var req = request(URL(string: "https://securetoken.googleapis.com/v1/token?key=\(key)")!)
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = "grant_type=refresh_token&refresh_token=\(token.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")".data(using: .utf8)
        let json = try await send(req)
        guard let next = json["refresh_token"] as? String, let id = json["id_token"] as? String,
              let uid = json["user_id"] as? String else { throw AuthError.emailFailed("No token came back.") }
        return Token(idToken: id, refreshToken: next, userID: uid)
    }

    /// A Firebase identity with no email or password, for accounts that live on the iPhone
    /// (username accounts, the checker, Google and Apple) so they can post leaderboard scores.
    /// Needs Authentication › Sign-in method › Anonymous turned on.
    func signUpAnonymous() async throws -> Token {
        let json = try await call("accounts:signUp", ["returnSecureToken": true])
        guard let id = json["idToken"] as? String, let refresh = json["refreshToken"] as? String,
              let uid = json["localId"] as? String else { throw AuthError.emailFailed("No account came back.") }
        return Token(idToken: id, refreshToken: refresh, userID: uid)
    }

    /// Sets a new password. Returns the new refresh token (Firebase replaces the session).
    func setPassword(_ password: String, idToken: String) async throws -> String? {
        let json = try await call("accounts:update", ["idToken": idToken, "password": password, "returnSecureToken": true])
        return json["refreshToken"] as? String
    }

    func deleteUser(idToken: String) async throws {
        _ = try await call("accounts:delete", ["idToken": idToken])
    }

    // MARK: plumbing

    /// Ephemeral: no cookies, no cache, nothing about the session written to disk.
    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        return URLSession(configuration: config)
    }()

    private static func session(from json: [String: Any]) -> Session? {
        guard let id = json["idToken"] as? String, let refresh = json["refreshToken"] as? String,
              let uid = json["localId"] as? String else { return nil }
        let name = (json["displayName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return Session(idToken: id, refreshToken: refresh, userID: uid,
                       email: (json["email"] as? String ?? "").lowercased(), username: name, verified: false)
    }

    private func request(_ url: URL) -> URLRequest {
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.httpMethod = "POST"
        // Lets the API key be restricted to this app in Google Cloud Console.
        if let bundle = Bundle.main.bundleIdentifier { req.setValue(bundle, forHTTPHeaderField: "X-Ios-Bundle-Identifier") }
        return req
    }

    private func call(_ method: String, _ body: [String: Any]) async throws -> [String: Any] {
        guard isConfigured else { throw AuthError.emailNotConfigured }
        var req = request(URL(string: "https://identitytoolkit.googleapis.com/v1/\(method)?key=\(key)")!)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await send(req)
    }

    private func send(_ req: URLRequest) async throws -> [String: Any] {
        var data = Data(), status = 0
        do {
            #if DEBUG
            if let (body, code) = try await Net.chaosReply() { data = body; status = code } else {
                let (d, r) = try await Self.session.data(for: req); data = d; status = (r as? HTTPURLResponse)?.statusCode ?? 0
            }
            #else
            let (d, r) = try await Self.session.data(for: req); data = d; status = (r as? HTTPURLResponse)?.statusCode ?? 0
            #endif
        } catch {
            throw AuthError.emailFailed("Check your connection and try again.")
        }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (200..<300).contains(status) else { throw Self.error(json) }
        return json
    }

    /// Turns Firebase's error codes into plain messages. Never says whether an email has an account.
    static func error(_ json: [String: Any]) -> AuthError {
        let raw = ((json["error"] as? [String: Any])?["message"] as? String) ?? (json["error"] as? String) ?? ""
        let code = raw.split(separator: " ").first.map(String.init)?.uppercased() ?? ""
        switch code {
        case "INVALID_LOGIN_CREDENTIALS", "INVALID_PASSWORD", "EMAIL_NOT_FOUND", "USER_NOT_FOUND",
             "INVALID_REFRESH_TOKEN", "TOKEN_EXPIRED", "INVALID_ID_TOKEN", "USER_DISABLED", "INVALID_GRANT":
            return .wrongDetails
        case "EMAIL_EXISTS": return .emailTaken
        case "INVALID_EMAIL": return .emailInvalid
        case "WEAK_PASSWORD": return .weakPassword
        case "TOO_MANY_ATTEMPTS_TRY_LATER": return .emailFailed("Too many tries from this iPhone. Wait a few minutes and try again.")
        case "ADMIN_ONLY_OPERATION":
            return .emailFailed("Anonymous sign-in is turned off in Firebase. Turn on Authentication › Sign-in method › Anonymous.")
        case "OPERATION_NOT_ALLOWED", "PASSWORD_LOGIN_DISABLED":
            return .emailFailed("Email sign-in is turned off in Firebase. Turn on Authentication › Sign-in method › Email/Password.")
        case "CREDENTIAL_TOO_OLD_LOGIN_AGAIN": return .emailFailed("Sign out and back in, then try again.")
        default:
            if raw.localizedCaseInsensitiveContains("API key") { return .emailFailed("The Firebase API key in Secrets.swift isn’t valid for this app.") }
            return .emailFailed("Something went wrong. Try again.")
        }
    }
}
