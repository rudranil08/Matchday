import Foundation
import CryptoKit
import AuthenticationServices

enum Role: String, Codable { case checker, fan }
enum Provider: String, Codable { case password, email, google, apple, guest }

struct Account: Codable, Equatable {
    let username: String
    let displayName: String
    let email: String?
    let role: Role
    let provider: Provider
    let password: PasswordHasher.Hashed?
    let created: Date

    /// Signs in with a password: a local account on this iPhone, or an email account.
    var usesPassword: Bool { provider == .password || provider == .email }
}

enum AuthError: LocalizedError {
    case wrongDetails, locked(seconds: Int), usernameTaken, usernameInvalid, weakPassword, mismatch
    case wrongPassword, samePassword, builtInAccount, confirmDelete
    case googleNotConfigured, googleFailed(String), appleFailed(String)
    case emailNotConfigured, emailInvalid, emailTaken, emailNotConfirmed, emailFailed(String)
    case guestMode, nameNotAllowed

    var errorDescription: String? {
        switch self {
        case .wrongDetails: "That username and password don’t match."
        case .wrongPassword: "That’s not your current password."
        case .samePassword: "Choose a password you haven’t used for this account."
        case .builtInAccount: "The checker account is built into the app, so it can’t be changed or deleted."
        case .confirmDelete: "Type DELETE to confirm."
        case .locked(let s): "Too many tries. Wait \(s) seconds and try again."
        case .usernameTaken: "That username is taken. Try another."
        case .usernameInvalid: "Usernames are 3–20 letters, numbers, dots or underscores."
        case .weakPassword: "Use at least 8 characters with a letter and a number."
        case .mismatch: "The passwords don’t match."
        case .googleNotConfigured: "Google sign-in isn’t set up yet. Add your Google client ID in Secrets.swift."
        case .googleFailed(let why): "Google sign-in didn’t finish. \(why)"
        case .appleFailed(let why): "Sign in with Apple didn’t finish. \(why)"
        case .emailNotConfigured: "Email accounts aren’t set up yet. Add your Firebase Web API key in Secrets.swift."
        case .emailInvalid: "Enter a valid email address."
        case .emailTaken: "That email already has an account. Sign in, or reset your password."
        case .emailNotConfirmed: "Verify your email first. Open the link we sent you, then sign in."
        case .emailFailed(let why): why
        case .guestMode: "The leaderboard isn’t available in guest mode."
        case .nameNotAllowed: "Please choose a different username."
        }
    }
}

/// Local accounts. Passwords are salted PBKDF2 hashes in the Keychain; plain passwords never touch disk.
@MainActor @Observable final class AuthStore {
    static let shared = AuthStore()

    private(set) var current: Account?
    /// AppState listens so it can bring back (or set aside) each account's leagues and clubs.
    var onAccountChange: ((Account?) -> Void)?
    var isSignedIn: Bool { current != nil }
    var isChecker: Bool { current?.role == .checker }
    /// Under-13 guest mode: nothing is collected or sent, no leaderboard.
    var isGuest: Bool { current?.provider == .guest }

    static let guestAccount = Account(username: "guest", displayName: "Guest", email: nil, role: .fan, provider: .guest,
                                      password: nil, created: Date(timeIntervalSince1970: 0))

    /// Guest mode for people under 13 (AgeGate). A local "account" so leagues and clubs can be saved.
    func signInAsGuest() {
        guard AgeGate.status == .child else { return }
        start(Self.guestAccount)
    }

    static let checkerUsername = "1234"

    // The built-in checker (highest) account. Only the salt and hash ship in the app.
    private static let checker = Account(
        username: checkerUsername,
        displayName: "Checker",
        email: nil,
        role: .checker,
        provider: .password,
        password: .init(
            salt: Data(hex: "09c1a21481513fd8e9bb507f654b9d53")!,
            hash: Data(hex: "21a4ab5f04824d342db63a30a732828b12a928812a98ee14bb9e7c9e582b2430")!,
            iterations: 310_000
        ),
        created: Date(timeIntervalSince1970: 1_792_368_000)
    )

    /// Remember me: on, the session is kept in the Keychain and survives closing the app.
    /// Off, it lives only in memory, so the next launch asks you to sign in again.
    var rememberMe = UserDefaults.standard.object(forKey: "auth.rememberMe") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(rememberMe, forKey: "auth.rememberMe")
            if let current { saveSession(current) }
        }
    }

    /// Last username signed in with a password (only with Remember me), to fill in the sign-in form.
    var lastUsername: String? { Keychain.get("auth.lastUsername").flatMap { String(data: $0, encoding: .utf8) } }

    // Brute-force protection: 5 wrong tries locks sign-in for 30 seconds.
    private var failures = UserDefaults.standard.integer(forKey: "auth.failures")
    private var lockedUntil = Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: "auth.lockedUntil"))

    private init() {
        Self.wipeIfReinstalled()
        UserDefaults.standard.removeObject(forKey: "auth.lastUsername") // moved to the Keychain
        if let name = Keychain.get("session").flatMap({ String(data: $0, encoding: .utf8) }) {
            current = account(named: name)
            if current?.provider == .email {
                refreshToken = Keychain.get("email.refresh").flatMap { String(data: $0, encoding: .utf8) }
                if refreshToken == nil { current = nil }
            }
        }
        #if DEBUG
        // Screenshot / UI-test hook: launch with -uiTestChecker to start signed in.
        // Compiled out of Release builds, so it can't ship.
        if ProcessInfo.processInfo.arguments.contains("-uiTestChecker") { current = Self.checker }
        #endif
    }

    private func key(_ username: String) -> String { "user:" + username.lowercased() }

    private func account(named username: String) -> Account? {
        if username.lowercased() == Self.checker.username { return Self.checker }
        if username == Self.guestAccount.username { return AgeGate.status == .child ? Self.guestAccount : nil }
        return Keychain.get(key(username)).flatMap { try? JSONDecoder().decode(Account.self, from: $0) }
    }

    /// Email accounts: the server session's refresh token. Kept in the Keychain only with Remember me.
    private var refreshToken: String?
    private let email = EmailAuth()
    var emailConfigured: Bool { email.isConfigured }

    private func saveSession(_ a: Account) {
        if rememberMe {
            Keychain.set(Data(a.username.utf8), for: "session")
            if let refreshToken { Keychain.set(Data(refreshToken.utf8), for: "email.refresh") }
            if a.usesPassword { Keychain.set(Data((a.provider == .email ? (a.email ?? a.username) : a.username).utf8), for: "auth.lastUsername") }
        } else {
            Keychain.delete("session")
            Keychain.delete("email.refresh")
            Keychain.delete("auth.lastUsername")
        }
    }

    /// On launch: check an email account's session is still good (and rotate its token).
    /// Offline is fine, you stay signed in; a session the server rejected signs you out.
    func refreshEmailSession() async {
        guard let a = current, a.provider == .email, let token = refreshToken else { return }
        do {
            refreshToken = try await email.refresh(token)
            saveSession(a)
        } catch AuthError.wrongDetails {
            signOut()
        } catch {}
    }

    private func start(_ a: Account) {
        onAccountChange?(a)
        current = a
        saveSession(a)
        failures = 0
        UserDefaults.standard.set(0, forKey: "auth.failures")
    }

    // MARK: sign in / up / out

    /// Hashing takes ~0.3 s on purpose, so it runs off the main thread.
    func signIn(username: String, password: String) async throws {
        if lockedUntil > Date() { throw AuthError.locked(seconds: Int(lockedUntil.timeIntervalSinceNow.rounded(.up))) }
        let name = username.trimmingCharacters(in: .whitespaces)
        if name.contains("@") {
            do {
                let session = try await email.signIn(email: name.lowercased(), password: password)
                failures = 0
                UserDefaults.standard.set(0, forKey: "auth.failures")
                guard session.verified else {
                    pendingVerification = session
                    throw AuthError.emailNotConfirmed
                }
                startEmail(session)
                return
            } catch AuthError.wrongDetails {
                try recordFailure()
            }
        }
        let found = account(named: name)
        let stored = found?.password
        let ok = await Task.detached(priority: .userInitiated) { () -> Bool in
            // Hash even when the user doesn't exist, so timing doesn't reveal valid usernames.
            guard let stored else { _ = PasswordHasher.hash(password); return false }
            return PasswordHasher.verify(password, against: stored)
        }.value
        guard ok, let found else { try recordFailure() }
        start(found)
    }

    /// Counts a wrong password; 5 in a row locks sign-in for 30 seconds. Always throws.
    private func recordFailure() throws -> Never {
        failures += 1
        UserDefaults.standard.set(failures, forKey: "auth.failures")
        if failures >= 5 {
            lockedUntil = Date().addingTimeInterval(30)
            failures = 0
            UserDefaults.standard.set(lockedUntil.timeIntervalSince1970, forKey: "auth.lockedUntil")
            UserDefaults.standard.set(0, forKey: "auth.failures")
            throw AuthError.locked(seconds: 30)
        }
        throw AuthError.wrongDetails
    }

    /// Signed in to an email account: remember the profile (no password) and the session.
    private func startEmail(_ s: EmailAuth.Session) {
        let name = s.email
        let existing = account(named: name)
        let a = Account(username: name, displayName: s.username ?? existing?.displayName ?? String(name.prefix { $0 != "@" }),
                        email: s.email, role: .fan, provider: .email, password: nil, created: existing?.created ?? Date())
        if let data = try? JSONEncoder().encode(a) { Keychain.set(data, for: key(name)) }
        refreshToken = s.refreshToken
        start(a)
    }

    static func isEmail(_ s: String) -> Bool {
        s.range(of: #"^[^@\s]+@[^@\s]+\.[A-Za-z]{2,}$"#, options: .regularExpression) != nil
    }

    /// Sign up. With Firebase set up, the account is an email account (so the password can be
    /// reset by email); returns true when the user has to verify their email first.
    @discardableResult
    func signUp(username: String, email address: String = "", password: String, confirm: String) async throws -> Bool {
        let name = username.trimmingCharacters(in: .whitespaces)
        if email.isConfigured {
            let mail = address.trimmingCharacters(in: .whitespaces).lowercased()
            guard Self.isEmail(mail) else { throw AuthError.emailInvalid }
            guard name.range(of: #"^[A-Za-z0-9._]{3,20}$"#, options: .regularExpression) != nil else { throw AuthError.usernameInvalid }
            guard NameFilter.isAllowed(name) else { throw AuthError.nameNotAllowed }
            guard Self.strength(password) >= 2 else { throw AuthError.weakPassword }
            guard password == confirm else { throw AuthError.mismatch }
            try useEmailAllowance()
            pendingVerification = try await email.signUp(email: mail, password: password, username: name)
            return true
        }
        guard name.range(of: #"^[A-Za-z0-9._]{3,20}$"#, options: .regularExpression) != nil else { throw AuthError.usernameInvalid }
        guard NameFilter.isAllowed(name) else { throw AuthError.nameNotAllowed }
        guard account(named: name) == nil else { throw AuthError.usernameTaken }
        guard Self.strength(password) >= 2 else { throw AuthError.weakPassword }
        guard password == confirm else { throw AuthError.mismatch }
        let hashed = await Task.detached(priority: .userInitiated) { PasswordHasher.hash(password) }.value
        let a = Account(username: name, displayName: name, email: nil, role: .fan, provider: .password, password: hashed, created: Date())
        if let data = try? JSONEncoder().encode(a) { Keychain.set(data, for: key(name)) }
        start(a)
        return false
    }

    // MARK: forgot password

    /// Signed up (or signed in) but the email isn't verified yet. Kept in memory only.
    private(set) var pendingVerification: EmailAuth.Session?

    /// "I've verified": checks with Firebase, then signs in.
    func finishVerification() async throws {
        guard let s = pendingVerification else { throw AuthError.emailFailed("Sign in again to continue.") }
        guard try await email.isVerified(idToken: s.idToken) else {
            throw AuthError.emailFailed("Not verified yet. Open the link in the email first (any device works).")
        }
        pendingVerification = nil
        startEmail(s)
    }

    func resendVerification() async throws {
        guard let s = pendingVerification else { throw AuthError.emailFailed("Sign in again to continue.") }
        try useEmailAllowance()
        try await email.sendVerification(idToken: s.idToken)
    }

    func cancelVerification() { pendingVerification = nil }

    // MARK: Firebase identity (leaderboard)

    /// A fresh Firebase ID token for the signed-in account. Email accounts use their own session;
    /// other accounts get a private anonymous Firebase identity, kept in the Keychain.
    func firebaseToken() async throws -> EmailAuth.Token {
        guard let a = current, a.provider != .guest else { throw AuthError.guestMode }
        // ID tokens last an hour: reuse one for 50 minutes instead of refreshing per request.
        if let c = tokenCache, c.user == a.username, c.until > Date() { return c.token }
        let t: EmailAuth.Token
        if a.provider == .email, let token = refreshToken {
            t = try await email.token(from: token)
            refreshToken = t.refreshToken
            saveSession(a)
        } else {
            let slot = "anon." + AppState.profileKey(a.username)
            var fresh: EmailAuth.Token?
            if let saved = Keychain.get(slot).flatMap({ String(data: $0, encoding: .utf8) }) {
                do {
                    fresh = try await email.token(from: saved)
                } catch AuthError.wrongDetails {
                    // Firebase no longer knows this identity: make a new one below.
                }
                // Any other error (no signal, a timeout) is thrown: never create a second identity
                // for the same person because of a network blip.
            }
            if fresh == nil { fresh = try await email.signUpAnonymous() }
            t = fresh!
            Keychain.set(Data(t.refreshToken.utf8), for: slot)
        }
        tokenCache = (a.username, t, Date().addingTimeInterval(50 * 60))
        return t
    }

    private var tokenCache: (user: String, token: EmailAuth.Token, until: Date)?

    /// The name shown on the leaderboard: a username, or a first name and initial. Never an email.
    /// Filtered: a name that fails NameFilter shows as "Player".
    var leaderboardName: String {
        let name = rawLeaderboardName
        return NameFilter.isAllowed(name) ? name : "Player"
    }

    private var rawLeaderboardName: String {
        guard let a = current else { return "Player" }
        switch a.provider {
        case .password, .email: return String(a.displayName.prefix(20))
        case .guest: return "Guest"
        case .google, .apple:
            let parts = a.displayName.split(separator: " ")
            guard let first = parts.first else { return "Player" }
            return parts.count > 1 ? "\(first) \(parts[1].prefix(1))." : String(first)
        }
    }

    // MARK: email allowance

    /// Each iPhone can ask for 15 emails (reset or sign-up, any address) in any rolling hour.
    static let emailsPerHour = 15

    /// When this iPhone asked for emails in the last hour. Kept in the Keychain, so deleting
    /// and reinstalling the app doesn't reset it.
    private var emailSends: [Date] {
        get {
            let all = Keychain.get("limit.emails").flatMap { try? JSONDecoder().decode([Date].self, from: $0) } ?? []
            return all.filter { $0 > Date().addingTimeInterval(-3600) }
        }
        set { Keychain.set((try? JSONEncoder().encode(newValue)) ?? Data(), for: "limit.emails") }
    }

    var emailsLeft: Int { max(0, Self.emailsPerHour - emailSends.count) }

    /// Counts one email request, or says how long until the next one is allowed.
    private func useEmailAllowance() throws {
        var sends = emailSends
        if sends.count >= Self.emailsPerHour, let oldest = sends.min() {
            let mins = max(1, Int((oldest.addingTimeInterval(3600).timeIntervalSinceNow / 60).rounded(.up)))
            throw AuthError.emailFailed("You’ve asked for \(Self.emailsPerHour) emails in the last hour. Try again in \(mins) min.")
        }
        sends.append(Date())
        emailSends = sends
    }

    func sendPasswordReset(to address: String) async throws {
        let mail = address.trimmingCharacters(in: .whitespaces).lowercased()
        guard Self.isEmail(mail) else { throw AuthError.emailInvalid }
        try useEmailAllowance()
        try await email.sendReset(email: mail)
    }

    func signInWithGoogle(_ profile: GoogleProfile) {
        let name = "google." + profile.subject
        let existing = account(named: name)
        let a = existing ?? Account(username: name, displayName: profile.name ?? profile.email ?? "Google user", email: profile.email,
                                    role: .fan, provider: .google, password: nil, created: Date())
        if existing == nil, let data = try? JSONEncoder().encode(a) { Keychain.set(data, for: key(name)) }
        start(a)
    }

    /// Apple only shares the name and email the first time; keep them from that first sign-in.
    func signInWithApple(_ credential: ASAuthorizationAppleIDCredential) {
        let name = "apple." + credential.user
        let existing = account(named: name)
        let full = [credential.fullName?.givenName, credential.fullName?.familyName].compactMap { $0 }.joined(separator: " ")
        let a = existing ?? Account(username: name, displayName: full.isEmpty ? (credential.email ?? "Apple user") : full,
                                    email: credential.email, role: .fan, provider: .apple, password: nil, created: Date())
        if existing == nil, let data = try? JSONEncoder().encode(a) { Keychain.set(data, for: key(name)) }
        start(a)
    }

    /// If the user stopped using Sign in with Apple for Matchday (Settings › Apple ID), sign them out.
    func checkAppleCredential() async {
        guard let c = current, c.provider == .apple else { return }
        let userID = String(c.username.dropFirst("apple.".count))
        let state = try? await ASAuthorizationAppleIDProvider().credentialState(forUserID: userID)
        if state == .revoked || state == .notFound { signOut() }
    }

    // MARK: reinstall cleanup

    /// iOS keeps Keychain items after an app is deleted. UserDefaults don't survive, so a missing
    /// install marker means a fresh install: remove any accounts left over from before.
    /// Existing setups (from before this marker existed) are recognised and kept.
    private static func wipeIfReinstalled() {
        let d = UserDefaults.standard
        guard !d.bool(forKey: "install.marker") else { return }
        let existingSetup = d.object(forKey: "onboarded") != nil || d.object(forKey: "myLeagues") != nil
        if !existingSetup {
            // The email allowance and the age answer outlive a reinstall on purpose.
            for item in Keychain.allAccounts() where item != "limit.emails" && item != "agegate" { Keychain.delete(item) }
        }
        d.set(true, forKey: "install.marker")
    }

    // MARK: change password / delete account

    /// Local password accounts only. Needs the current password; the new one gets a fresh salt.
    func changePassword(current: String, new: String, confirm: String) async throws {
        guard let a = current_, a.usesPassword else { throw AuthError.wrongPassword }
        guard a.role != .checker else { throw AuthError.builtInAccount }
        if a.provider == .email {
            guard Self.strength(new) >= 2 else { throw AuthError.weakPassword }
            guard new == confirm else { throw AuthError.mismatch }
            guard new != current else { throw AuthError.samePassword }
            let s: EmailAuth.Session
            do { s = try await email.signIn(email: a.email ?? a.username, password: current) } catch AuthError.wrongDetails { throw AuthError.wrongPassword }
            refreshToken = try await email.setPassword(new, idToken: s.idToken) ?? s.refreshToken
            saveSession(a)
            return
        }
        guard let stored = a.password else { throw AuthError.wrongPassword }
        let ok = await Task.detached(priority: .userInitiated) { PasswordHasher.verify(current, against: stored) }.value
        guard ok else { throw AuthError.wrongPassword }
        guard Self.strength(new) >= 2 else { throw AuthError.weakPassword }
        guard new == confirm else { throw AuthError.mismatch }
        guard new != current else { throw AuthError.samePassword }
        let hashed = await Task.detached(priority: .userInitiated) { PasswordHasher.hash(new) }.value
        let updated = Account(username: a.username, displayName: a.displayName, email: a.email, role: a.role,
                              provider: a.provider, password: hashed, created: a.created)
        if let data = try? JSONEncoder().encode(updated) { Keychain.set(data, for: key(a.username)) }
        self.current = updated
    }

    /// Deletes the signed-in account from this iPhone. Password accounts confirm with their
    /// password; Google and Apple accounts confirm by typing DELETE.
    func deleteAccount(confirmation: String) async throws {
        guard let a = current_ else { return }
        guard a.role != .checker, a.provider != .guest else { throw AuthError.builtInAccount }
        // 1. Confirm it's really them.
        var emailSession: EmailAuth.Session?
        if a.provider == .email {
            do { emailSession = try await email.signIn(email: a.email ?? a.username, password: confirmation) } catch AuthError.wrongDetails { throw AuthError.wrongPassword }
        } else if a.provider == .password, let stored = a.password {
            let ok = await Task.detached(priority: .userInitiated) { PasswordHasher.verify(confirmation, against: stored) }.value
            guard ok else { throw AuthError.wrongPassword }
        } else {
            guard confirmation.trimmingCharacters(in: .whitespaces).uppercased() == "DELETE" else { throw AuthError.confirmDelete }
        }
        // 2. Remove their leaderboard name and scores, then their Firebase identity. If this can't be
        //    done (no signal), stop here: better to try again than leave their name behind.
        let failed = AuthError.emailFailed("Couldn’t remove your leaderboard scores. Check your connection and try again.")
        if let s = emailSession {
            do { try await Leaderboard.shared.deleteAll(uid: s.userID, idToken: s.idToken) } catch { throw failed }
            try await email.deleteUser(idToken: s.idToken)
        } else {
            let slot = "anon." + AppState.profileKey(a.username)
            if let saved = Keychain.get(slot).flatMap({ String(data: $0, encoding: .utf8) }) {
                var token: EmailAuth.Token?
                do { token = try await email.token(from: saved) } catch AuthError.wrongDetails {
                    // That identity is already gone from Firebase.
                } catch { throw failed }
                if let token {
                    do { try await Leaderboard.shared.deleteAll(uid: token.userID, idToken: token.idToken) } catch { throw failed }
                    try? await email.deleteUser(idToken: token.idToken)
                }
                Keychain.delete(slot)
            }
        }
        // 3. Then the account and everything saved on this iPhone.
        tokenCache = nil
        UserDefaults.standard.removeObject(forKey: "quiz." + AppState.profileKey(a.username))
        Keychain.delete(key(a.username))
        UserDefaults.standard.removeObject(forKey: AppState.profileKey(a.username))
        if [a.username, a.email].contains(where: { $0?.lowercased() == lastUsername?.lowercased() }) { Keychain.delete("auth.lastUsername") }
        signOut()
    }

    private var current_: Account? { current }

    func signOut() {
        onAccountChange?(nil)
        tokenCache = nil
        current = nil
        refreshToken = nil
        Keychain.delete("session")
        Keychain.delete("email.refresh")
    }

    /// Usernames only, for the checker panel. Never passwords.
    func accountNames() -> [String] {
        [Self.checker.username] + Keychain.allAccounts().filter { $0.hasPrefix("user:") }.map { String($0.dropFirst(5)) }
    }

    /// 0 = too short, 1 = weak, 2 = good, 3 = strong.
    static func strength(_ p: String) -> Int {
        guard p.count >= 8 else { return 0 }
        let letter = p.range(of: "[A-Za-z]", options: .regularExpression) != nil
        let digit = p.range(of: "[0-9]", options: .regularExpression) != nil
        let symbol = p.range(of: "[^A-Za-z0-9]", options: .regularExpression) != nil
        let mixed = p.range(of: "[a-z]", options: .regularExpression) != nil && p.range(of: "[A-Z]", options: .regularExpression) != nil
        guard letter && digit else { return 1 }
        return (symbol || mixed) && p.count >= 10 ? 3 : 2
    }
}

// MARK: Google sign-in (OAuth 2.0 with PKCE, no SDK)

struct GoogleProfile {
    let subject: String
    let email: String?
    let name: String?
}

/// Builds the Google sign-in request and swaps the returned code for the user's profile.
/// Uses Apple's secure web sign-in sheet; the app never sees the Google password.
struct GoogleOAuth {
    let clientID = Secrets.googleClientID
    let verifier: String = PasswordHasher.randomBytes(32).base64URL
    let state: String = PasswordHasher.randomBytes(16).base64URL

    var isConfigured: Bool { clientID.hasSuffix(".apps.googleusercontent.com") }

    /// iOS client IDs use the reversed ID as the redirect scheme.
    var callbackScheme: String { "com.googleusercontent.apps." + clientID.replacingOccurrences(of: ".apps.googleusercontent.com", with: "") }
    private var redirect: String { callbackScheme + ":/oauth2redirect" }

    var authURL: URL {
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
        var c = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        c.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirect),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: "openid email profile"),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state),
            .init(name: "prompt", value: "select_account"),
        ]
        return c.url!
    }

    func profile(from callback: URL) async throws -> GoogleProfile {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard items.first(where: { $0.name == "state" })?.value == state else { throw AuthError.googleFailed("The response didn’t match this request.") }
        guard let code = items.first(where: { $0.name == "code" })?.value else {
            throw AuthError.googleFailed(items.first(where: { $0.name == "error" })?.value ?? "No code returned.")
        }
        var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let form = ["client_id": clientID, "code": code, "code_verifier": verifier, "grant_type": "authorization_code", "redirect_uri": redirect]
        req.httpBody = form.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")" }
            .joined(separator: "&").data(using: .utf8)
        let (data, _) = try await EmailAuth.session.data(for: req)
        struct Token: Decodable { let id_token: String? }
        guard let idToken = try JSONDecoder().decode(Token.self, from: data).id_token else { throw AuthError.googleFailed("No identity token.") }
        // The ID token came straight from Google's token endpoint over TLS (with our PKCE verifier),
        // so its payload can be read here. Still check who issued it, who it's for and that it's current.
        // A server that trusts these tokens should also verify the signature against Google's keys.
        let parts = idToken.split(separator: ".")
        guard parts.count >= 2, let payload = Data(base64URL: String(parts[1])),
              let claims = try JSONSerialization.jsonObject(with: payload) as? [String: Any],
              let sub = claims["sub"] as? String else { throw AuthError.googleFailed("Couldn’t read the profile.") }
        try Self.validate(claims, clientID: clientID)
        return GoogleProfile(subject: sub, email: claims["email"] as? String, name: claims["name"] as? String)
    }

    /// Issuer must be Google, audience must be this app, and the token must not have expired.
    static func validate(_ claims: [String: Any], clientID: String, now: Date = Date()) throws {
        let iss = claims["iss"] as? String
        guard iss == "accounts.google.com" || iss == "https://accounts.google.com" else {
            throw AuthError.googleFailed("The sign-in didn’t come from Google.")
        }
        let aud = claims["aud"] as? String ?? (claims["aud"] as? [String])?.first
        guard aud == clientID else { throw AuthError.googleFailed("The sign-in was meant for a different app.") }
        guard let exp = (claims["exp"] as? NSNumber)?.doubleValue, Date(timeIntervalSince1970: exp) > now else {
            throw AuthError.googleFailed("The sign-in has expired. Try again.")
        }
        if let iat = (claims["iat"] as? NSNumber)?.doubleValue, Date(timeIntervalSince1970: iat) > now.addingTimeInterval(300) {
            throw AuthError.googleFailed("The sign-in time looks wrong. Check your iPhone’s clock.")
        }
        if let verified = claims["email_verified"] as? Bool, !verified, claims["email"] != nil {
            throw AuthError.googleFailed("That Google account’s email isn’t verified.")
        }
    }
}

extension Data {
    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    init?(base64URL: String) {
        var s = base64URL.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s += "=" }
        self.init(base64Encoded: s)
    }
}
