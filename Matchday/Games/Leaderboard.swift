import Foundation

/// Daily and all-time quiz leaderboards in Cloud Firestore (REST, no SDK), in the same Firebase
/// project as sign-in. Security rules (README) make sure each player can only write their own
/// score, only for today, and only within the daily maximum.
///
///   days/{day}/scores/{uid}  name, points, correct, answered, updated
///   players/{uid}            name, total, lastDay, lastPoints, updated
enum LeaderboardError: Error { case transient }

actor Leaderboard {
    static let shared = Leaderboard()

    struct Entry: Identifiable, Equatable {
        let id: String
        let name: String
        let points: Int
    }

    enum Board: String, CaseIterable { case today = "Today", allTime = "All time" }

    private var cache: [String: (at: Date, entries: [Entry])] = [:]

    var isConfigured: Bool { !Secrets.firebaseProjectID.isEmpty && EmailAuth().isConfigured }

    private var base: String {
        "https://firestore.googleapis.com/v1/projects/\(Secrets.firebaseProjectID)/databases/(default)/documents"
    }

    // MARK: writing

    /// Posts today's score after an answer (retrying through dropped connections and busy replies).
    /// The all-time total is updated once, when the round is finished.
    func submit(day: Int, points: Int, correct: Int, answered: Int, final: Bool, name: String) async throws {
        try await retrying {
            let token = try await AuthStore.shared.firebaseToken()
            let now = ISO8601DateFormatter().string(from: Date())
            try await self.patch("days/\(day)/scores/\(token.userID)", token: token.idToken, fields: [
                "name": .string(name), "points": .int(points), "correct": .int(correct),
                "answered": .int(answered), "updated": .time(now),
            ])
        }
        guard final else { return }
        try await retrying {
            let token = try await AuthStore.shared.firebaseToken()
            let now = ISO8601DateFormatter().string(from: Date())
            let player = try await self.get("players/\(token.userID)", token: token.idToken)
            let total = player["total"]?.intValue ?? 0
            let lastDay = player["lastDay"]?.intValue ?? -1
            let lastPoints = player["lastPoints"]?.intValue ?? 0
            let newTotal = (lastDay == day ? total - lastPoints : total) + points
            try await self.patch("players/\(token.userID)", token: token.idToken, fields: [
                "name": .string(name), "total": .int(newTotal), "lastDay": .int(day),
                "lastPoints": .int(points), "updated": .time(now),
            ])
        }
        cache = [:]
    }

    /// Up to 3 tries, waiting about 0.6 s then 1.8 s (with jitter, so 1,000 phones don't retry in step).
    /// Only for failures that can pass: no signal, timeouts, "busy" (429) and server errors.
    private func retrying(_ work: () async throws -> Void) async throws {
        var attempt = 0
        while true {
            do { return try await work() } catch LeaderboardError.transient where attempt < 2 {
                attempt += 1
                let wait = 0.6 * pow(3, Double(attempt - 1)) * Double.random(in: 0.7...1.3)
                try await Task.sleep(for: .seconds(wait))
            } catch LeaderboardError.transient {
                throw AuthError.emailFailed("Couldn’t reach the leaderboard. Your score is saved and will be posted next time.")
            }
        }
    }

    // MARK: reporting

    /// Reports a leaderboard name for review. Reports are private: only you (in the Firebase console) can read them.
    func report(_ entry: Entry) async throws {
        let token = try await AuthStore.shared.firebaseToken()
        let fields: [String: Value] = [
            "reportedUid": .string(entry.id), "name": .string(entry.name),
            "reporter": .string(token.userID), "created": .time(ISO8601DateFormatter().string(from: Date())),
        ]
        try await retrying { _ = try await self.send(URL(string: self.base + "/reports")!, method: "POST", token: token.idToken,
                                                     json: ["fields": fields.mapValues(\.json)]) }
    }

    // MARK: deleting

    /// Account deletion: the all-time record and every daily score since the leaderboard opened,
    /// in batches of 400 deletes (one request each). Deleting a day the player never played is harmless.
    func deleteAll(uid: String, idToken: String) async throws {
        let root = "projects/\(Secrets.firebaseProjectID)/databases/(default)/documents"
        var names = ["\(root)/players/\(uid)"]
        for day in DailyQuiz.firstDay...DailyQuiz.today { names.append("\(root)/days/\(day)/scores/\(uid)") }
        let url = URL(string: base + ":commit")!
        for start in stride(from: 0, to: names.count, by: 400) {
            let writes = names[start..<min(start + 400, names.count)].map { ["delete": $0] }
            try await retrying { _ = try await self.send(url, method: "POST", token: idToken, json: ["writes": Array(writes)]) }
        }
        cache = [:]
    }

    // MARK: reading

    /// The top of a board, kept for a minute. The hub needs 5 rows, the full board 10: small reads
    /// keep a busy day inside Firestore's free 50,000 reads.
    func top(_ board: Board, day: Int, limit: Int = 10, force: Bool = false) async throws -> (entries: [Entry], me: String) {
        let token = try await AuthStore.shared.firebaseToken()
        let key = "\(board.rawValue)-\(day)-\(limit)"
        if !force, let hit = cache[key], Date().timeIntervalSince(hit.at) < 60 { return (hit.entries, token.userID) }
        let (path, collection, field) = board == .today ? ("days/\(day)", "scores", "points") : ("", "players", "total")
        let body: [String: Any] = ["structuredQuery": [
            "from": [["collectionId": collection]],
            "orderBy": [["field": ["fieldPath": field], "direction": "DESCENDING"]],
            "limit": limit,
        ]]
        let url = URL(string: base + (path.isEmpty ? "" : "/" + path) + ":runQuery")!
        var rows: [[String: Any]] = []
        try await retrying { rows = try await self.send(url, method: "POST", token: token.idToken, json: body) as? [[String: Any]] ?? [] }
        let entries: [Entry] = rows.compactMap { row in
            guard let doc = row["document"] as? [String: Any], let name = doc["name"] as? String,
                  let fields = doc["fields"] as? [String: Any] else { return nil }
            let values = fields.mapValues(Value.init)
            return Entry(id: String(name.split(separator: "/").last ?? ""), name: values["name"]?.stringValue ?? "Player",
                         points: values[field]?.intValue ?? 0)
        }
        cache[key] = (Date(), entries)
        return (entries, token.userID)
    }

    // MARK: Firestore REST plumbing

    enum Value {
        case string(String), int(Int), time(String), other

        init(_ any: Any) {
            let d = any as? [String: Any] ?? [:]
            if let s = d["stringValue"] as? String { self = .string(s) }
            else if let i = d["integerValue"] as? String, let n = Int(i) { self = .int(n) }
            else if let t = d["timestampValue"] as? String { self = .time(t) }
            else { self = .other }
        }

        var json: [String: Any] {
            switch self {
            case .string(let s): ["stringValue": s]
            case .int(let n): ["integerValue": String(n)]
            case .time(let t): ["timestampValue": t]
            case .other: ["nullValue": NSNull()]
            }
        }
        var intValue: Int? { if case .int(let n) = self { n } else { nil } }
        var stringValue: String? { if case .string(let s) = self { s } else { nil } }
    }

    private func get(_ path: String, token: String) async throws -> [String: Value] {
        let json = try await send(URL(string: base + "/" + path)!, method: "GET", token: token, json: nil) as? [String: Any]
        return ((json?["fields"] as? [String: Any]) ?? [:]).mapValues(Value.init)
    }

    private func patch(_ path: String, token: String, fields: [String: Value]) async throws {
        var c = URLComponents(string: base + "/" + path)!
        c.queryItems = fields.keys.sorted().map { URLQueryItem(name: "updateMask.fieldPaths", value: $0) }
        _ = try await send(c.url!, method: "PATCH", token: token, json: ["fields": fields.mapValues(\.json)])
    }

    private func send(_ url: URL, method: String, token: String, json: Any?) async throws -> Any {
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let bundle = Bundle.main.bundleIdentifier { req.setValue(bundle, forHTTPHeaderField: "X-Ios-Bundle-Identifier") }
        if let json {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: json)
        }
        var data = Data(), status = 0
        do {
            #if DEBUG
            if let (body, code) = try await Net.chaosReply() { data = body; status = code } else {
                let (d, r) = try await EmailAuth.session.data(for: req); data = d; status = (r as? HTTPURLResponse)?.statusCode ?? 0
            }
            #else
            let (d, r) = try await EmailAuth.session.data(for: req); data = d; status = (r as? HTTPURLResponse)?.statusCode ?? 0
            #endif
        } catch { throw LeaderboardError.transient }
        let body = (try? JSONSerialization.jsonObject(with: data)) ?? [:]
        guard (200..<300).contains(status) else {
            if status == 404, method == "GET" { return [String: Any]() }
            let message = ((body as? [String: Any])?["error"] as? [String: Any])?["message"] as? String ?? ""
            if status == 403 || message.contains("PERMISSION_DENIED") {
                throw AuthError.emailFailed("The leaderboard isn’t set up yet: turn on Firestore and paste the rules from the README.")
            }
            if message.contains("has not been used") || message.contains("does not exist") {
                throw AuthError.emailFailed("Turn on Firestore Database in the Firebase console to use the leaderboard.")
            }
            if status == 429 || status >= 500 || status == 0 { throw LeaderboardError.transient }
            throw AuthError.emailFailed("Couldn’t reach the leaderboard. Try again.")
        }
        return body
    }
}
