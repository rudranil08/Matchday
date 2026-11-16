import SwiftUI

/// Settings in the app's own style: a header in your club's colour with your account,
/// then cards for your leagues and clubs, developer tools, extras, data and privacy.
struct SettingsView: View {
    @Environment(\.palette) private var t
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(AppState.self) private var app
    @Environment(AuthStore.self) private var auth
    @State private var choosing = false
    @State private var confirmSignOut = false
    @State private var changingPassword = false
    @State private var deleting = false
    @State private var storage: Int?
    @State private var clearing = false

    private func securityNote(_ u: Account) -> String {
        switch u.provider {
        case .password: "Your password is never stored, only a salted hash in the Keychain."
        case .email: "Your password is kept only as a hash by Firebase, never on this iPhone."
        case .google, .apple: "Signed in with \(u.provider == .apple ? "Apple" : "Google"). Matchday never sees that password."
        case .guest: "Guest mode: no account, no email and no leaderboard. Everything stays on this iPhone."
        }
    }

    private var reorderHint: Bool { if #available(iOS 27, *) { true } else { false } }

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    var body: some View {
        let band = app.primaryClub.map { ClubColors(team: $0.team, dark: scheme == .dark) } ?? .cobalt

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header(band)

                    VStack(alignment: .leading, spacing: 24) {
                        leaguesCard
                        accountCard
                        if auth.isChecker { developerCard }
                        extrasCard
                        dataCard
                        legalCard
                        signOutButton
                        Text("Matchday \(version)")
                            .mutedStyle(t).frame(maxWidth: .infinity).padding(.bottom, 24)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                }
            }
            .background(t.bg)
            .ignoresSafeArea(edges: .top)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.font(AppFont.bold(16)).foregroundStyle(band.on)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            .fullScreenCover(isPresented: $choosing) { LeaguesAndClubsEditor() }
            .sheet(isPresented: $changingPassword) { ChangePasswordSheet() }
            .sheet(isPresented: $deleting) { DeleteAccountSheet() }
            .confirmationDialog("Sign out of Matchday?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) { app.signOut() }
            } message: {
                Text("Your leagues and clubs stay saved with your account, ready for when you sign back in.")
            }
        }
    }

    // MARK: header

    private func header(_ band: ClubColors) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("SETTINGS").font(AppFont.display(32))
            if let user = auth.current {
                HStack(spacing: 14) {
                    ZStack {
                        Circle().fill(band.on.opacity(0.16))
                        if user.usesPassword {
                            Text(initials(user.displayName)).font(AppFont.display(20))
                        } else {
                            Image(systemName: user.provider == .apple ? "apple.logo" : user.provider == .guest ? "person.fill" : "globe")
                                .font(.system(size: 24, weight: .semibold))
                        }
                    }
                    .frame(width: 60, height: 60)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(user.displayName).font(AppFont.bold(19)).lineLimit(1)
                            if user.role == .checker {
                                Text("CHECKER").font(AppFont.bold(10)).tracking(1)
                                    .padding(.horizontal, 7).padding(.vertical, 3)
                                    .background(band.on.opacity(0.2), in: Capsule())
                            }
                        }
                        Text(subtitle(user)).font(AppFont.medium(14)).opacity(0.85).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .foregroundStyle(band.on)
        .padding(.horizontal, 20).padding(.top, 70).padding(.bottom, 26)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(band.solid)
    }

    private func initials(_ name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        let s = parts.compactMap(\.first).map(String.init).joined()
        return s.isEmpty ? "?" : s.uppercased()
    }

    private func subtitle(_ u: Account) -> String {
        switch u.provider {
        case .password: "@\(u.username) · Matchday account"
        case .email: "\(u.email ?? u.username) · Matchday account"
        case .google: u.email ?? "Signed in with Google"
        case .apple: u.email ?? "Signed in with Apple"
        case .guest: "Guest mode"
        }
    }

    // MARK: cards

    private var leaguesCard: some View {
        SettingsCard(title: "Your leagues and clubs",
                     footer: "News and Form switch between these leagues." + (reorderHint ? " Drag to reorder, or swipe right to make one your main league." : " Press and hold a league to make it your main one.")) {
            ReorderableLeagues { league in
                let i = app.myLeagues.firstIndex(of: league) ?? 0
                let club = app.clubs(in: league).first
                VStack(spacing: 0) {
                    HStack(spacing: 14) {
                        if let club {
                            CrestView(team: club.team, size: 40, circle: true)
                                .overlay(Circle().stroke(t.line, lineWidth: 1))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(club?.name ?? "No club yet").font(AppFont.bold(16)).foregroundStyle(t.ink)
                            Text(league.name + (i == 0 ? " · main league" : "")).mutedStyle(t)
                        }
                        Spacer()
                        if #available(iOS 27, *), app.myLeagues.count > 1 {
                            Image(systemName: "line.3.horizontal").foregroundStyle(t.muted).accessibilityHidden(true)
                        }
                    }
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                    if i < app.myLeagues.count - 1 { Divider().overlay(t.line) }
                }
                .background(t.surface)
            }
            let extra = app.clubs.filter { !app.myLeagues.contains($0.league) }
            if !extra.isEmpty {
                Divider().overlay(t.line)
                HStack {
                    Text("Also following").font(AppFont.semibold(14)).foregroundStyle(t.ink)
                    Spacer()
                    Text(extra.map(\.short).joined(separator: ", ")).mutedStyle(t).lineLimit(1)
                }
                .padding(.vertical, 12)
            }
            Divider().overlay(t.line)
            Button { choosing = true } label: {
                HStack {
                    Text("Edit leagues and clubs").font(AppFont.semibold(16)).foregroundStyle(t.accent)
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(t.muted)
                }
                .frame(height: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder private var accountCard: some View {
        if let user = auth.current {
            SettingsCard(title: "Account", footer: securityNote(user) + (user.role == .checker
                         ? " The checker account is built into the app, so it can’t be changed or deleted."
                         : "")) {
                if user.provider == .guest {
                    SettingsRow(icon: "lock.iphone", tint: Color(hex: "2f9e6b"), title: "On this iPhone only",
                                detail: "Your leagues, clubs and quiz progress aren’t sent anywhere")
                        .padding(.vertical, 10)
                }
                if user.usesPassword && user.role != .checker {
                    Button { changingPassword = true } label: {
                        HStack {
                            SettingsRow(icon: "key.fill", tint: t.accent, title: "Change password", detail: "Needs your current password")
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(t.muted)
                        }
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    Divider().overlay(t.line)
                }
                if user.provider != .guest {
                Toggle(isOn: Binding(get: { auth.rememberMe }, set: { auth.rememberMe = $0 })) {
                    SettingsRow(icon: "person.crop.circle.badge.checkmark", tint: Color(hex: "3a7bd5"), title: "Remember me",
                                detail: "Stay signed in on this iPhone")
                }
                .tint(t.accent)
                .padding(.vertical, 10)
                }
                if user.role != .checker && user.provider != .guest {
                    Divider().overlay(t.line)
                    Button { deleting = true } label: {
                        HStack {
                            SettingsRow(icon: "trash.fill", tint: t.red, title: "Delete account", detail: "Removes your account, leaderboard scores and saved data")
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(t.muted)
                        }
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var developerCard: some View {
        SettingsCard(title: "Developer", footer: app.newUserMode
                     ? "On: closing and reopening Matchday signs the checker out and starts it as a new user. Other accounts aren’t affected."
                     : "Only the checker account can see this.") {
            Toggle(isOn: Binding(get: { app.newUserMode }, set: { app.newUserMode = $0 })) {
                SettingsRow(icon: "person.badge.plus", tint: t.accent, title: "New user mode", detail: "Full onboarding on every fresh launch")
            }
            .tint(t.accent)
            .padding(.vertical, 10)
            Divider().overlay(t.line)
            NavigationLink { CheckerView() } label: {
                HStack {
                    SettingsRow(icon: "checkmark.shield", tint: Color(hex: "2f9e6b"), title: "Checker tools", detail: "Data feeds, accounts, resets")
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(t.muted)
                }
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
        }
    }

    private var extrasCard: some View {
        SettingsCard(title: "On your iPhone") {
            SettingsRow(icon: "square.grid.2x2", tint: Color(hex: "e07b00"), title: "Widgets",
                        detail: "Hold the Home Screen › Edit › Add Widget › Matchday. Lock Screen too.")
                .padding(.vertical, 10)
            Divider().overlay(t.line)
            SettingsRow(icon: "waveform", tint: Color(hex: "8e5bea"), title: "Siri & Shortcuts",
                        detail: "“Who’s top of the league in Matchday?”")
                .padding(.vertical, 10)
        }
    }

    private var dataCard: some View {
        SettingsCard(title: "Data and privacy",
                     footer: "Club names and colours identify the clubs. Matchday isn’t affiliated with or endorsed by any league, club or player.") {
            SettingsRow(icon: "sportscourt", tint: t.red, title: "Football data",
                        detail: MatchdayAPI.lastMode == .sample
                        ? "Sample data: the data server has no provider key yet"
                        : "Licensed from Sportmonks: tables, results, player stats and injuries")
                .padding(.vertical, 10)
            Divider().overlay(t.line)
            SettingsRow(icon: "hand.raised", tint: t.accent, title: "No ads, no tracking",
                        detail: auth.isGuest
                        ? "Everything stays on this iPhone"
                        : auth.current?.provider == .email
                        ? "Leagues and clubs stay on this iPhone. Sign-in and quiz scores use Google Firebase"
                        : "Leagues and clubs stay on this iPhone. Quiz scores and your leaderboard name use Google Firebase")
                .padding(.vertical, 10)
            Divider().overlay(t.line)
            HStack {
                SettingsRow(icon: "internaldrive", tint: t.muted, title: "Saved on this iPhone",
                            detail: (storage.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) + " · " } ?? "")
                            + "the latest data, for instant opening and no signal. Old data is removed automatically")
                Spacer(minLength: 8)
                Button(clearing ? "Clearing…" : "Clear") {
                    clearing = true
                    Task {
                        await DataStore.shared.clearAll()
                        ImageCache.shared.removeAll()
                        storage = await DataStore.shared.storageUsed()
                        clearing = false
                    }
                }
                .font(AppFont.bold(14)).foregroundStyle(t.accent).disabled(clearing || storage == 0)
            }
            .padding(.vertical, 10)
            .task { storage = await DataStore.shared.storageUsed() }
        }
    }

    @State private var legal: LegalDoc?

    private var legalCard: some View {
        SettingsCard(title: "Legal") {
            ForEach(Array(LegalDoc.all.enumerated()), id: \.element.id) { i, doc in
                if i > 0 { Divider().overlay(t.line) }
                Button { legal = doc } label: {
                    HStack {
                        Text(doc.title).font(AppFont.semibold(16)).foregroundStyle(t.ink)
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(t.muted)
                    }
                    .frame(height: 48).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(item: $legal) { LegalView(doc: $0) }
    }

    private var signOutButton: some View {
        Button { confirmSignOut = true } label: {
            Text("Sign out").font(AppFont.bold(16)).foregroundStyle(t.red)
                .frame(maxWidth: .infinity).frame(height: 50)
                .background(t.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(t.line, lineWidth: 1))
        }
    }
}

/// A titled card section.
private struct SettingsCard<Content: View>: View {
    @Environment(\.palette) private var t
    let title: String
    var footer: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(AppFont.semibold(12)).tracking(1.2).foregroundStyle(t.muted).padding(.leading, 4)
            VStack(alignment: .leading, spacing: 0) { content }
                .padding(.horizontal, 16).padding(.vertical, 6)
                .card()
            if let footer {
                Text(footer).font(AppFont.regular(13)).foregroundStyle(t.muted).padding(.horizontal, 4)
            }
        }
    }
}

/// Icon tile + title + detail.
private struct SettingsRow: View {
    @Environment(\.palette) private var t
    let icon: String
    let tint: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 32, height: 32).background(tint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(AppFont.bold(15)).foregroundStyle(t.ink)
                Text(detail).font(AppFont.regular(13)).foregroundStyle(t.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: change password

private struct ChangePasswordSheet: View {
    @Environment(\.palette) private var t
    @Environment(\.dismiss) private var dismiss
    @State private var current = ""
    @State private var new = ""
    @State private var confirm = ""
    @State private var error: String?
    @State private var busy = false
    @State private var done = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Choose a new password you don’t use anywhere else.").font(AppFont.regular(15)).foregroundStyle(t.muted)
                    box { PasswordField(title: "Current password", text: $current) }
                    box { PasswordField(title: "New password", text: $new, isNew: true) }
                    box { PasswordField(title: "Confirm new password", text: $confirm, isNew: true) }
                    if let error { Text(error).font(AppFont.medium(14)).foregroundStyle(t.red) }
                    if done {
                        Label("Password changed", systemImage: "checkmark.circle.fill").font(AppFont.bold(15)).foregroundStyle(Color(hex: "2f9e6b"))
                    }
                    Button(action: save) {
                        HStack(spacing: 10) {
                            if busy { ProgressView().tint(.white) }
                            Text("Change password").font(AppFont.bold(17))
                        }
                        .foregroundStyle(.white).frame(maxWidth: .infinity).frame(height: 52)
                        .background(t.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .disabled(busy || current.isEmpty || new.isEmpty || confirm.isEmpty)
                    .opacity(current.isEmpty || new.isEmpty || confirm.isEmpty ? 0.6 : 1)
                }
                .padding(20)
            }
            .background(t.bg)
            .navigationTitle("Change password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .sensoryFeedback(.success, trigger: done)
        }
        .presentationDetents([.medium, .large])
    }

    private func box<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        c().font(AppFont.medium(17)).foregroundStyle(Color(hex: "121726"))
            .padding(.horizontal, 14).frame(height: 52)
            .background(Palette.light.bg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Palette.light.line, lineWidth: 1))
    }

    private func save() {
        busy = true
        error = nil
        Task {
            defer { busy = false }
            do {
                try await AuthStore.shared.changePassword(current: current, new: new, confirm: confirm)
                current = ""; new = ""; confirm = ""
                done = true
                try? await Task.sleep(for: .seconds(0.9))
                dismiss()
            } catch {
                self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                current = ""
            }
        }
    }
}

// MARK: delete account

private struct DeleteAccountSheet: View {
    @Environment(\.palette) private var t
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var app
    @Environment(AuthStore.self) private var auth
    @State private var confirmation = ""
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        let isPassword = auth.current?.usesPassword == true
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 34)).foregroundStyle(t.red)
                    Text("DELETE YOUR ACCOUNT?").font(AppFont.display(22)).foregroundStyle(t.ink)
                    VStack(alignment: .leading, spacing: 6) {
                        Label(auth.current?.provider == .email ? "Your Matchday account and email sign-in are deleted" : "Your account is removed from this iPhone",
                              systemImage: "person.crop.circle.badge.xmark")
                        Label("Your leaderboard name and every score are removed", systemImage: "list.number")
                        Label("Your leagues, clubs and quiz best are erased", systemImage: "star.slash")
                        Label("Saved offline data is cleared", systemImage: "internaldrive")
                    }
                    .font(AppFont.medium(14)).foregroundStyle(t.ink)
                    Text("This can’t be undone.").font(AppFont.bold(14)).foregroundStyle(t.red)

                    Group {
                        if isPassword {
                            PasswordField(title: "Your password", text: $confirmation)
                        } else {
                            TextField("", text: $confirmation, prompt: Text("Type DELETE").foregroundStyle(Palette.light.muted))
                                .textInputAutocapitalization(.characters).autocorrectionDisabled()
                        }
                    }
                    .font(AppFont.medium(17)).foregroundStyle(Color(hex: "121726"))
                    .padding(.horizontal, 14).frame(height: 52)
                    .background(Palette.light.bg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Palette.light.line, lineWidth: 1))

                    if let error { Text(error).font(AppFont.medium(14)).foregroundStyle(t.red) }

                    Button(action: delete) {
                        HStack(spacing: 10) {
                            if busy { ProgressView().tint(.white) }
                            Text("Delete account").font(AppFont.bold(17))
                        }
                        .foregroundStyle(.white).frame(maxWidth: .infinity).frame(height: 52)
                        .background(t.red, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .disabled(busy || confirmation.isEmpty)
                    .opacity(confirmation.isEmpty ? 0.6 : 1)
                }
                .padding(20)
            }
            .background(t.bg)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .presentationDetents([.large])
    }

    private func delete() {
        busy = true
        error = nil
        Task {
            defer { busy = false }
            do {
                try await auth.deleteAccount(confirmation: confirmation)
                app.eraseLocalData()
                dismiss()
            } catch {
                self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                confirmation = ""
            }
        }
    }
}
