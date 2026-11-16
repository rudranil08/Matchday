import SwiftUI
import AuthenticationServices

/// First run: welcome → sign in / create account / Google → pick your club → into the app.
struct OnboardingView: View {
    enum Step: Equatable { case welcome, age, signIn, signUp, league, club }

    @State var step: Step
    @State private var leagues: [League] = []
    @Environment(AppState.self) private var app

    var body: some View {
        ZStack {
            PitchBackground()
            switch step {
            case .welcome:
                WelcomeStep(step: $step).transition(.opacity.combined(with: .move(edge: .bottom)))
            case .age:
                AgeStep(onDone: { _ in step = .welcome }, onBack: { step = .welcome })
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            case .signIn, .signUp:
                AuthStep(mode: step == .signUp ? .signUp : .signIn, step: $step).transition(.move(edge: .bottom).combined(with: .opacity))
            case .league:
                LeagueSelectView(selected: $leagues) { step = .club }
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
            case .club:
                ClubSelectView(leagues: leagues, onBack: { step = .league }) { app.finishOnboarding() }
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: step)
        .onAppear { if leagues.isEmpty { leagues = app.myLeagues } }
        .preferredColorScheme(.dark)
        // Signed in: new users pick a league and club; returning users go straight home (RootView fades across).
        .onChange(of: AuthStore.shared.isSignedIn) { _, signedIn in
            // This account's saved leagues (none for a new account) start the league step.
            leagues = app.myLeagues
            if signedIn && !app.onboarded { step = .league }
        }
    }
}

// MARK: welcome

private struct WelcomeStep: View {
    @Binding var step: OnboardingView.Step
    @State private var error: String?
    @State private var googleBusy = false
    /// Asked once per iPhone before any account: decides between sign-in and guest mode.
    @State private var age = AgeGate.status
    @Environment(\.webAuthenticationSession) private var webAuth

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
            Text("MATCH").font(AppFont.displayBlack(64)).foregroundStyle(.white)
            Text("DAY.").font(AppFont.displayBlack(64)).foregroundStyle(Color(hex: "8ea2ff"))
            Text("Tables, player form, injuries and news for the Premier League, LaLiga, Bundesliga and Ligue\u{00A0}1.")
                .font(AppFont.regular(17)).foregroundStyle(.white.opacity(0.85)).padding(.top, 12)
            Text("Flick the ball. Try to score.").font(AppFont.semibold(13)).foregroundStyle(.white.opacity(0.5)).padding(.top, 8)
            Spacer()

            VStack(spacing: 10) {
                switch age {
                case nil:
                    Button { step = .age } label: { primaryLabel("Get started") }
                        .accessibilityIdentifier("welcome.start")
                case .child:
                    // Guest mode: no account, no email, no Firebase ID, no leaderboard. Everything stays here.
                    Button { AuthStore.shared.signInAsGuest() } label: { primaryLabel("Continue") }
                        .accessibilityIdentifier("welcome.guest")
                    Text("You’ll use Matchday as a guest. Everything stays on this iPhone.")
                        .font(AppFont.medium(13)).foregroundStyle(.white.opacity(0.6)).frame(maxWidth: .infinity)
                    LegalAgreement(light: true).padding(.top, 4)
                case .adult:
                SignInWithAppleButton(.continue) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    switch result {
                    case .success(let auth):
                        guard let credential = auth.credential as? ASAuthorizationAppleIDCredential else { return }
                        AuthStore.shared.signInWithApple(credential)
                    case .failure(let e):
                        if (e as? ASAuthorizationError)?.code == .canceled { return }
                        error = AuthError.appleFailed(e.localizedDescription).localizedDescription
                    }
                }
                .signInWithAppleButtonStyle(.white)
                .frame(height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityIdentifier("apple")
                Button { Task { await google() } } label: {
                    HStack(spacing: 10) {
                        if googleBusy { ProgressView().tint(.white) }
                        Text("Continue with Google").font(AppFont.bold(17))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 54)
                    .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .disabled(googleBusy)
                Button { step = .signIn } label: {
                    Text("Sign in with email or username").font(AppFont.bold(17)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 54)
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.white.opacity(0.35), lineWidth: 1))
                }
                Button { step = .signUp } label: {
                    (Text("New to Matchday? ").foregroundStyle(.white.opacity(0.6)) + Text("Create an account").foregroundStyle(.white))
                        .font(AppFont.semibold(15))
                        .frame(maxWidth: .infinity).frame(height: 44)
                }
                if let error {
                    Text(error).font(AppFont.medium(14)).foregroundStyle(Color(hex: "ff9a9a")).frame(maxWidth: .infinity, alignment: .leading)
                }
                LegalAgreement(light: true)
                }
            }
        }
        .padding(.horizontal, 24).padding(.bottom, 24)
    }

    private func google() async {
        error = nil
        let oauth = GoogleOAuth()
        guard oauth.isConfigured else { error = AuthError.googleNotConfigured.localizedDescription; return }
        googleBusy = true
        defer { googleBusy = false }
        do {
            let callback = try await webAuth.authenticate(using: oauth.authURL, callbackURLScheme: oauth.callbackScheme, preferredBrowserSession: .ephemeral)
            let profile = try await oauth.profile(from: callback)
            AuthStore.shared.signInWithGoogle(profile)
        } catch let e as ASWebAuthenticationSessionError where e.code == .canceledLogin {
            // User closed the sheet: nothing to report.
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

func primaryLabel(_ title: String, busy: Bool = false) -> some View {
    HStack(spacing: 10) {
        if busy { ProgressView().tint(Color(hex: "121726")) }
        Text(title).font(AppFont.bold(17))
    }
    .foregroundStyle(Color(hex: "121726"))
    .frame(maxWidth: .infinity).frame(height: 54)
    .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
}

// MARK: sign in / create account

private struct AuthStep: View {
    enum Mode { case signIn, signUp }
    let mode: Mode
    @Binding var step: OnboardingView.Step

    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirm = ""
    @State private var error: String?
    @State private var busy = false
    @State private var attempts = 0
    @State private var remember = AuthStore.shared.rememberMe
    @State private var forgot = false
    @State private var checkEmail = false
    @FocusState private var focus: Field?
    enum Field { case email, username, password, confirm }

    /// Sign-up asks for an email when email accounts (and password reset) are set up.
    private var wantsEmail: Bool { mode == .signUp && AuthStore.shared.emailConfigured }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { step = .welcome } label: {
                Label("Back", systemImage: "chevron.left").font(AppFont.semibold(15)).foregroundStyle(.white)
            }
            .padding(.top, 8)
            Spacer()

            VStack(alignment: .leading, spacing: 14) {
                Text(mode == .signIn ? "SIGN IN" : "CREATE ACCOUNT").font(AppFont.display(26)).foregroundStyle(Color(hex: "121726"))
                Text(mode == .signIn ? "Welcome back." : "Pick a username and a password you don’t use anywhere else.")
                    .font(AppFont.regular(15)).foregroundStyle(Palette.light.muted)

                if checkEmail {
                    CheckEmailNote(email: email) { checkEmail = false; step = .signIn }
                } else {
                if wantsEmail {
                    field("Email") {
                        TextField("", text: $email, prompt: Text("Email").foregroundStyle(Palette.light.muted))
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focus, equals: .email)
                            .submitLabel(.next)
                            .onSubmit { focus = .username }
                    }
                }
                field(signInLabel) {
                    TextField("", text: $username, prompt: Text(signInLabel).foregroundStyle(Palette.light.muted))
                        .textContentType(.username)
                        .keyboardType(mode == .signIn && AuthStore.shared.emailConfigured ? .emailAddress : .default)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .username)
                        .submitLabel(.next)
                        .onSubmit { focus = .password }
                }
                field("Password") {
                    PasswordField(title: "Password", text: $password, isNew: mode == .signUp)
                        .focused($focus, equals: .password)
                        .submitLabel(mode == .signUp ? .next : .go)
                        .onSubmit { mode == .signUp ? (focus = .confirm) : submit() }
                }
                if mode == .signUp {
                    StrengthMeter(password: password)
                    field("Confirm password") {
                        PasswordField(title: "Confirm password", text: $confirm, isNew: true)
                            .focused($focus, equals: .confirm)
                            .submitLabel(.go)
                            .onSubmit(submit)
                    }
                }
                HStack(alignment: .center) {
                    RememberMe(on: $remember)
                    if mode == .signIn {
                        Button("Forgot password?") { focus = nil; forgot = true }
                            .font(AppFont.semibold(15)).foregroundStyle(Palette.light.accent)
                    }
                }
                if let error {
                    Text(error).font(AppFont.medium(14)).foregroundStyle(Palette.light.red)
                        .transition(.opacity)
                }
                Button(action: submit) {
                    HStack(spacing: 10) {
                        if busy { ProgressView().tint(.white) }
                        Text(mode == .signIn ? "Sign in" : "Create account").font(AppFont.bold(17))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 52)
                    .background(Palette.light.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .disabled(busy || username.isEmpty || password.isEmpty || (wantsEmail && email.isEmpty))
                .opacity(username.isEmpty || password.isEmpty || (wantsEmail && email.isEmpty) ? 0.6 : 1)
                if mode == .signUp { LegalAgreement() }
                }

                if !checkEmail {
                    Button { step = mode == .signIn ? .signUp : .signIn; error = nil } label: {
                        Text(mode == .signIn ? "New here? Create an account" : "Already have an account? Sign in")
                            .font(AppFont.semibold(14)).foregroundStyle(Palette.light.accent)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(20)
            .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .modifier(Shake(attempts: attempts))
            .sensoryFeedback(.error, trigger: attempts)
        }
        .padding(.horizontal, 20).padding(.bottom, 20)
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-uiTestForgot") { forgot = true }
            #endif
            if mode == .signIn, username.isEmpty, let last = AuthStore.shared.lastUsername {
                username = last
                focus = .password
            } else {
                focus = wantsEmail ? .email : .username
            }
        }
        .onChange(of: remember) { _, on in AuthStore.shared.rememberMe = on }
        .sheet(isPresented: $forgot) {
            ForgotPasswordSheet(email: username.contains("@") ? username : "")
        }
    }

    private var signInLabel: String {
        mode == .signIn && AuthStore.shared.emailConfigured ? "Email or username" : "Username"
    }

    private func field<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .font(AppFont.medium(17))
            .foregroundStyle(Color(hex: "121726"))
            .padding(.horizontal, 14).frame(height: 52)
            .background(Palette.light.bg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Palette.light.line, lineWidth: 1))
            .accessibilityLabel(label)
    }

    private func submit() {
        guard !busy else { return }
        busy = true
        error = nil
        Task {
            defer { busy = false }
            do {
                if mode == .signIn {
                    try await AuthStore.shared.signIn(username: username, password: password)
                } else {
                    let confirmFirst = try await AuthStore.shared.signUp(username: username, email: email, password: password, confirm: confirm)
                    if confirmFirst { withAnimation { checkEmail = true } }
                }
                password = ""; confirm = ""
            } catch AuthError.emailNotConfirmed {
                // Signed in with the right password but the email isn't verified yet.
                password = ""
                email = username.trimmingCharacters(in: .whitespaces).lowercased()
                withAnimation { checkEmail = true }
            } catch {
                password = ""; confirm = ""
                self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                withAnimation(.default) { attempts += 1 }
                focus = .password
            }
        }
    }
}

/// After sign-up (or signing in before verifying): open the link Google emailed, then continue.
private struct CheckEmailNote: View {
    let email: String
    let onBack: () -> Void
    @State private var busy = false
    @State private var error: String?
    @State private var resent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "envelope.badge").font(.system(size: 30, weight: .semibold)).foregroundStyle(Palette.light.accent)
            Text("Verify your email").font(AppFont.bold(18)).foregroundStyle(Color(hex: "121726"))
            Text("We emailed a link to \(email). Open it on any device (this iPhone or a computer), then come back and tap I’ve verified.")
                .font(AppFont.regular(15)).foregroundStyle(Palette.light.muted)
            if let error { Text(error).font(AppFont.medium(14)).foregroundStyle(Palette.light.red) }
            if resent { Text("Sent again. Check your spam folder too.").font(AppFont.medium(14)).foregroundStyle(Color(hex: "2f9e6b")) }
            Button(action: finish) {
                HStack(spacing: 10) {
                    if busy { ProgressView().tint(.white) }
                    Text("I’ve verified").font(AppFont.bold(17))
                }
                .foregroundStyle(.white).frame(maxWidth: .infinity).frame(height: 52)
                .background(Palette.light.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .disabled(busy)
            LinkRow([
                ("Open Mail", openMail),
                ("Resend email", resend),
                ("Back", { AuthStore.shared.cancelVerification(); onBack() }),
            ])
        }
        .transition(.opacity)
    }

    private func finish() {
        busy = true
        error = nil
        Task {
            defer { busy = false }
            do { try await AuthStore.shared.finishVerification() } catch {
                self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func resend() {
        error = nil
        resent = false
        Task {
            do { try await AuthStore.shared.resendVerification(); resent = true } catch {
                self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}

/// Small text buttons under a main button: equal widths, centred, with thin dividers between.
struct LinkRow: View {
    let items: [(String, () -> Void)]
    init(_ items: [(String, () -> Void)]) { self.items = items }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                if i > 0 { Rectangle().fill(Palette.light.line).frame(width: 1, height: 18) }
                Button(action: item.1) {
                    Text(item.0).font(AppFont.semibold(14)).foregroundStyle(Palette.light.accent)
                        .lineLimit(1).minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

@MainActor func openMail() {
    if let url = URL(string: "message://") { UIApplication.shared.open(url) }
}

/// "Remember me": stay signed in after closing the app. Off, Matchday asks again next launch.
private struct RememberMe: View {
    @Binding var on: Bool

    var body: some View {
        Button { on.toggle() } label: {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(on ? Palette.light.accent : .clear)
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(on ? Palette.light.accent : Palette.light.line, lineWidth: 1.5))
                    if on { Image(systemName: "checkmark").font(.system(size: 12, weight: .heavy)).foregroundStyle(.white) }
                }
                .frame(width: 22, height: 22)
                Text("Remember me").font(AppFont.semibold(15)).foregroundStyle(Color(hex: "121726"))
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: on)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Secure password entry with a show / hide toggle. Hidden by default; the text is
/// kept out of screenshots and the app switcher, and is never logged or stored.
struct PasswordField: View {
    let title: String
    @Binding var text: String
    var isNew = false
    @State private var visible = false

    var body: some View {
        HStack {
            Group {
                if visible {
                    TextField("", text: $text, prompt: Text(title).foregroundStyle(Palette.light.muted))
                } else {
                    SecureField("", text: $text, prompt: Text(title).foregroundStyle(Palette.light.muted))
                }
            }
            .textContentType(isNew ? .newPassword : .password)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .privacySensitive()

            Button { visible.toggle() } label: {
                Image(systemName: visible ? "eye.slash" : "eye").foregroundStyle(Palette.light.muted).frame(width: 44, height: 44)
            }
            .accessibilityLabel(visible ? "Hide password" : "Show password")
        }
    }
}

struct StrengthMeter: View {
    let password: String

    var body: some View {
        let s = AuthStore.strength(password)
        let label = ["Too short (8+ characters)", "Weak: add a number and a letter", "Good", "Strong"][s]
        let color = [Palette.light.muted, Palette.light.red, Palette.light.yellowText, Color(hex: "2f9e6b")][s]
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    Capsule().fill(i < s ? color : Palette.light.line).frame(height: 4)
                }
            }
            .frame(width: 90)
            Text(password.isEmpty ? "8+ characters, a letter and a number" : label)
                .font(AppFont.medium(12)).foregroundStyle(password.isEmpty ? Palette.light.muted : color)
        }
        .animation(.easeOut(duration: 0.2), value: s)
    }
}

/// Shakes the card on a wrong password.
private struct Shake: GeometryEffect {
    var attempts: Int
    var animatableData: CGFloat
    init(attempts: Int) { self.attempts = attempts; animatableData = CGFloat(attempts) }
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 8 * sin(animatableData * .pi * 4), y: 0))
    }
}
