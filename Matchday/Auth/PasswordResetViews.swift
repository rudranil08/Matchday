import SwiftUI

// Forgot password: enter your email → Google emails a link → open it on any device and choose a
// new password on Google's page → sign in with it here.

private let p = Palette.light
private let ink = Color(hex: "121726")

func authBox<C: View>(@ViewBuilder _ c: () -> C) -> some View {
    c().font(AppFont.medium(17)).foregroundStyle(ink)
        .padding(.horizontal, 14).frame(height: 52)
        .background(p.bg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(p.line, lineWidth: 1))
}

func authPrimary(_ title: String, busy: Bool) -> some View {
    HStack(spacing: 10) {
        if busy { ProgressView().tint(.white) }
        Text(title).font(AppFont.bold(17))
    }
    .foregroundStyle(.white).frame(maxWidth: .infinity).frame(height: 52)
    .background(p.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
}

struct ForgotPasswordSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var email: String
    @State private var sent = false
    @State private var busy = false
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        let auth = AuthStore.shared
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !auth.emailConfigured {
                        notice(icon: "envelope.badge.shield.half.filled", title: "Not set up yet",
                               text: "Password reset by email needs a Firebase project. Add its Web API key in Secrets.swift (see the README).")
                    } else if sent {
                        notice(icon: "envelope.open.fill", title: "Check your email",
                               text: "If \(email) has a Matchday account, we’ve emailed it a link. Open it on any device (this iPhone or a computer), choose a new password, then sign in here with it.")
                        Button { dismiss() } label: { authPrimary("Back to sign in", busy: false) }
                        LinkRow([("Open Mail", openMail), ("Send again", { if auth.emailsLeft > 0 { sent = false } })])
                        allowanceNote(auth.emailsLeft).frame(maxWidth: .infinity)
                    } else {
                        Text("Enter the email you signed up with and we’ll send you a link to choose a new password.")
                            .font(AppFont.regular(15)).foregroundStyle(p.muted)
                        authBox {
                            TextField("", text: $email, prompt: Text("Email").foregroundStyle(p.muted))
                                .textContentType(.emailAddress)
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .focused($focused)
                                .submitLabel(.send)
                                .onSubmit(send)
                        }
                        if let error { Text(error).font(AppFont.medium(14)).foregroundStyle(p.red) }
                        Button(action: send) { authPrimary("Send reset email", busy: busy) }
                            .disabled(busy || email.isEmpty)
                            .opacity(email.isEmpty ? 0.6 : 1)
                        allowanceNote(auth.emailsLeft)
                        Text("Accounts made with a username only, Google or Apple can’t be reset by email.")
                            .font(AppFont.regular(13)).foregroundStyle(p.muted)
                    }
                }
                .padding(20)
                .animation(.easeInOut(duration: 0.25), value: sent)
            }
            .background(p.surface.ignoresSafeArea())
            .navigationTitle("Forgot password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .sensoryFeedback(.success, trigger: sent)
            .onAppear { focused = email.isEmpty }
        }
        .environment(\.colorScheme, .light)
        .presentationDetents([.large])
    }

    private func send() {
        guard !busy else { return }
        busy = true
        error = nil
        Task {
            defer { busy = false }
            do {
                try await AuthStore.shared.sendPasswordReset(to: email)
                withAnimation { sent = true }
            } catch {
                self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}

/// "12 of 15 emails left this hour" on this iPhone.
@MainActor private func allowanceNote(_ left: Int) -> some View {
    Label("\(left) of \(AuthStore.emailsPerHour) emails left this hour on this iPhone", systemImage: "envelope.badge")
        .font(AppFont.medium(13))
        .foregroundStyle(left == 0 ? p.red : p.muted)
}

private func notice(icon: String, title: String, text: String) -> some View {
    VStack(alignment: .leading, spacing: 10) {
        Image(systemName: icon).font(.system(size: 30, weight: .semibold)).foregroundStyle(p.accent)
        Text(title).font(AppFont.bold(18)).foregroundStyle(ink)
        Text(text).font(AppFont.regular(15)).foregroundStyle(p.muted).fixedSize(horizontal: false, vertical: true)
    }
}
