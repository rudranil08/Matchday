import Foundation

/// Who runs Matchday and how to reach them. Fill these in before release: they appear in the
/// Privacy Policy, Terms and Copyright pages (in the app and in the web versions under /legal).
enum LegalInfo {
    /// Your name or company, as it should appear in the policies. Empty shows "the Matchday team".
    static let operatorName = ""
    /// Where people send privacy requests, copyright notices and reports. Empty shows the App Store fallback.
    static let contactEmail = ""
    /// Public URLs once the /legal pages are hosted (App Store Connect needs the privacy one).
    static let privacyURL = ""
    static let termsURL = ""
    static let effectiveDate = "20 October 2026"

    static var who: String { operatorName.isEmpty ? "the Matchday team" : operatorName }
    static var contact: String {
        contactEmail.isEmpty ? "the support link on Matchday’s App Store page" : contactEmail
    }
}

/// A legal page: a title and its sections. The same text is used for the web versions.
struct LegalDoc: Identifiable, Hashable {
    let id: String
    let title: String
    let intro: String
    let sections: [(heading: String, body: String)]

    static func == (a: LegalDoc, b: LegalDoc) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }

    static let all: [LegalDoc] = [privacy, terms, copyright]

    // MARK: privacy

    static let privacy = LegalDoc(id: "privacy", title: "Privacy Policy", intro: """
        This policy explains what Matchday collects, why, who it’s shared with and the choices you have. \
        It’s run by \(LegalInfo.who). Questions or requests: \(LegalInfo.contact). Effective \(LegalInfo.effectiveDate).
        """, sections: [
        ("The short version", """
            No ads, no analytics, no tracking and no selling of data. Your leagues, clubs and saved match data stay on your iPhone. \
            Sign-in and the quiz leaderboard use Google Firebase. Your leaderboard name and points are visible to other players.
            """),
        ("What we collect", """
            • Account details. A username and password (accounts kept on this iPhone store only a salted hash of the password, in the iPhone Keychain), \
            or an email address and password (kept by Google Firebase, which stores the password only as a hash).
            • Sign in with Apple or Google. The name and email address Apple or Google share with us. Matchday never sees those passwords.
            • A Firebase user ID. Created when you sign in with email, or when you first open Games with any other account, so your quiz scores can be saved.
            • Quiz results. Your daily points, how many answers you got right, and the name shown on the leaderboard: your username, or your first name and the first letter of your last name.
            • Reports. If you report a leaderboard name, we keep the reported name, its ID and your ID.
            """),
        ("What stays on your iPhone", """
            Your leagues and clubs, followed clubs, saved match data, quiz progress, game streaks and settings. \
            Catch me up summaries are written on the device by Apple Intelligence: the match data isn’t sent anywhere for this.
            """),
        ("Services we use", """
            • Google Firebase (Authentication and Cloud Firestore) for email accounts, sign-in and the leaderboard. Data is stored on Google’s servers, which may be in the United States.
            • Sign in with Apple and Google Sign-In, if you choose them.
            • Matchday’s own data server, hosted by Cloudflare, provides the tables, results, fixtures, player stats and injuries, which it licenses from Sportmonks. When the app loads them, the server receives your device’s IP address and standard request details, as any website would. It doesn’t receive your account details, and Sportmonks never sees your device.
            """),
        ("Why we use it", """
            To run your account, show the leaderboard, keep the service secure and handle reports and abuse. \
            Where EU or UK law applies, we rely on providing the service you asked for (contract) and our legitimate interest in keeping it safe and fair.
            """),
        ("Who can see what", """
            Other signed-in players can see your leaderboard name and points. Nobody else sees your email address. We don’t sell or share your personal information for advertising.
            """),
        ("How long we keep it", """
            Until you delete your account. Deleting your account in Settings removes your account, your leaderboard name and scores, and the data Matchday saved on your iPhone. \
            Reports are kept as long as needed to deal with them.
            """),
        ("Your choices and rights", """
            You can delete your account at any time in Settings › Account › Delete account. You can also ask us for a copy of your data, \
            or to correct or delete it, by contacting \(LegalInfo.contact). If you’re in the EU or UK you can also complain to your data protection authority. \
            If you’re in California you have the right to know about and delete your personal information, and we don’t sell or share it.
            """),
        ("Children", """
            Accounts, sign-in and the leaderboard are for people aged 13 and over. People under 13 use Matchday as a guest: \
            no account, no email, no Firebase ID and no leaderboard, and everything stays on the iPhone. \
            If you believe a child under 13 has given us personal information, contact \(LegalInfo.contact) and we’ll delete it.
            """),
        ("Security", """
            Connections are encrypted. Passwords are never stored in readable form. Sign-in tokens are kept in the iPhone Keychain, on this device only.
            """),
        ("Changes", """
            If this policy changes, we’ll update the date above and, for important changes, tell you in the app.
            """),
    ])

    // MARK: terms

    static let terms = LegalDoc(id: "terms", title: "Terms of Use", intro: """
        These terms apply when you use Matchday, run by \(LegalInfo.who). By creating an account or using the app you agree to them. Effective \(LegalInfo.effectiveDate).
        """, sections: [
        ("Who can use Matchday", """
            Anyone can use Matchday as a guest. You need to be 13 or older to create an account, sign in or appear on the leaderboard.
            """),
        ("Your account", """
            Keep your password private and don’t share your account. You’re responsible for what happens on it. You can delete it at any time in Settings.
            """),
        ("Names and fair play", """
            Your username or leaderboard name must not be offensive, hateful, sexual, threatening, or pretend to be someone else, and must not include personal details like phone numbers. \
            Don’t cheat, automate answers, or try to change scores. We may change or remove a name, remove scores, or suspend accounts that break these rules, and repeat offenders are banned.
            """),
        ("Football data", """
            Tables, results, fixtures, stats and injuries are licensed from Sportmonks. They may be late or wrong, and Form scores are Matchday’s own estimate, not official statistics. \
            Club and league names and club colours are used only to identify them. Matchday isn’t affiliated with or endorsed by any league, club or player.
            """),
        ("Matchday’s content", """
            The app, its design and its own text belong to \(LegalInfo.who). Please don’t copy or resell them.
            """),
        ("No warranty", """
            Matchday is provided as it is, free of charge, without guarantees that it will always be available or error-free. \
            To the extent the law allows, we aren’t liable for indirect losses from using it. Nothing here limits rights you have under the law where you live.
            """),
        ("Ending", """
            You can stop using Matchday and delete your account at any time. We may suspend or end access for anyone who breaks these terms.
            """),
        ("Changes and contact", """
            We may update these terms and will change the date above when we do. Questions: \(LegalInfo.contact).
            """),
    ])

    // MARK: copyright

    static let copyright = LegalDoc(id: "copyright", title: "Copyright and Content", intro: """
        Players can choose a username, which other players see on the leaderboard. Here’s how to report a name or a copyright problem.
        """, sections: [
        ("Report a name", """
            In Games, press and hold a name on the leaderboard and choose Report. Reported names are reviewed and removed if they break the Terms of Use. \
            You can also hide a name for yourself straight away.
            """),
        ("Copyright notices", """
            If you believe something in Matchday infringes your copyright, send a notice to our designated agent at \(LegalInfo.contact) with: \
            your contact details; the work you believe is infringed; what in Matchday you believe infringes it and where it appears; \
            a statement that you believe in good faith the use isn’t authorised; a statement that the notice is accurate and, under penalty of perjury, \
            that you’re the owner or authorised to act for them; and your physical or electronic signature.
            """),
        ("Counter-notices", """
            If something of yours was removed and you believe that was a mistake, you can send a counter-notice to the same address with your contact details, \
            what was removed, a statement under penalty of perjury that you believe it was removed by mistake, and your consent to the jurisdiction of the courts where you live.
            """),
        ("Repeat infringers", """
            Accounts that repeatedly infringe copyright or break the naming rules are banned from posting to the leaderboard.
            """),
    ])
}
