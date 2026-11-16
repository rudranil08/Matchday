import SwiftUI

/// Neutral age check, asked once on this iPhone before any account or sign-in.
/// Only the result is kept (13 or over / under 13), never the date of birth, in the Keychain so
/// deleting and reinstalling the app doesn't reset it. Under 13: guest mode, nothing leaves the iPhone.
enum AgeGate {
    enum Status: String { case adult, child }
    private static let slot = "agegate"

    static var status: Status? {
        get { Keychain.get(slot).flatMap { String(data: $0, encoding: .utf8) }.flatMap(Status.init) }
        set {
            if let newValue { Keychain.set(Data(newValue.rawValue.utf8), for: slot) } else { Keychain.delete(slot) }
        }
    }

    /// Age from a month and year, counting the birthday as the last day of that month (the cautious reading).
    static func isUnder13(month: Int, year: Int, now: Date = Date()) -> Bool {
        let cal = Calendar(identifier: .gregorian)
        let today = cal.dateComponents([.year, .month], from: now)
        var age = (today.year ?? 0) - year
        if (today.month ?? 1) <= month { age -= 1 }
        return age < 13
    }
}

/// "What's your date of birth?": month and year, both empty until chosen, no hints.
struct AgeStep: View {
    var onDone: (AgeGate.Status) -> Void
    var onBack: (() -> Void)?
    @State private var month: Int?
    @State private var year: Int?

    // The phone’s own calendar, so month names are in the person’s language.
    private let months = Calendar.current.standaloneMonthSymbols
    private var years: [Int] {
        let now = Calendar(identifier: .gregorian).component(.year, from: Date())
        return Array(stride(from: now, through: now - 100, by: -1))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let onBack {
                Button(action: onBack) {
                    Label("Back", systemImage: "chevron.left").font(AppFont.semibold(15)).foregroundStyle(.white)
                }
                .padding(.top, 8)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 14) {
                Text("BEFORE YOU START").font(AppFont.display(26)).foregroundStyle(Color(hex: "121726"))
                Text("What’s your date of birth?").font(AppFont.bold(17)).foregroundStyle(Color(hex: "121726"))
                // Two wheels, each starting on a blank row: no answer is pre-chosen.
                HStack(spacing: 0) {
                    Picker("Month", selection: $month) {
                        Text("Month").foregroundStyle(Palette.light.muted).tag(Int?.none)
                        ForEach(1...12, id: \.self) { m in Text(months[m - 1]).tag(Int?.some(m)) }
                    }
                    .frame(maxWidth: .infinity)
                    Picker("Year", selection: $year) {
                        Text("Year").foregroundStyle(Palette.light.muted).tag(Int?.none)
                        ForEach(years, id: \.self) { y in Text(String(y)).tag(Int?.some(y)) }
                    }
                    .frame(width: 120)
                }
                .pickerStyle(.wheel)
                .font(AppFont.medium(17))
                .foregroundStyle(Color(hex: "121726"))
                .frame(height: 150).clipped()
                .background(Palette.light.bg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Palette.light.line, lineWidth: 1))
                .environment(\.colorScheme, .light)
                Text("Matchday asks everyone this once. Your date of birth isn’t saved or sent anywhere.")
                    .font(AppFont.regular(13)).foregroundStyle(Palette.light.muted)
                Button {
                    guard let month, let year else { return }
                    let status: AgeGate.Status = AgeGate.isUnder13(month: month, year: year) ? .child : .adult
                    AgeGate.status = status
                    onDone(status)
                } label: {
                    Text("Continue").font(AppFont.bold(17)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 52)
                        .background(Palette.light.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .disabled(month == nil || year == nil)
                .opacity(month == nil || year == nil ? 0.6 : 1)
                .accessibilityIdentifier("age.continue")
            }
            .padding(20)
            .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .padding(.horizontal, 20).padding(.bottom, 20)
    }
}
