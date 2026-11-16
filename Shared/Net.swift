import Foundation

/// One network session for every request: short timeouts (a stuck request fails fast and the
/// saved copy is shown), and an HTTP cache on disk so repeat requests are quick.
enum Net {
    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 40
        config.waitsForConnectivity = false
        config.httpMaximumConnectionsPerHost = 6
        // Small: replies are compact JSON, and images are rare.
        config.urlCache = URLCache(memoryCapacity: 8 * 1024 * 1024, diskCapacity: 40 * 1024 * 1024)
        config.requestCachePolicy = .useProtocolCachePolicy
        return URLSession(configuration: config)
    }()

    #if DEBUG
    /// Test hook: -uiTestOffline makes every feed request fail as if there were no signal.
    static let simulateOffline = ProcessInfo.processInfo.arguments.contains("-uiTestOffline")
    /// Test hook: -uiTestChaos makes the network behave like an overloaded service: slow replies,
    /// dropped connections, server errors and garbage bodies. Used to prove nothing crashes.
    static let chaos = ProcessInfo.processInfo.arguments.contains("-uiTestChaos")

    /// Applies chaos to one request: may wait, throw, or replace the reply.
    static func chaosReply() async throws -> (Data, Int)? {
        guard chaos else { return nil }
        try? await Task.sleep(for: .milliseconds(Int.random(in: 0...3000)))
        switch Int.random(in: 0..<100) {
        case 0..<20: throw URLError(.timedOut)
        case 20..<30: throw URLError(.networkConnectionLost)
        case 30..<45: return (Data("{\"error\":{\"message\":\"Service unavailable\"}}".utf8), 503)
        case 45..<55: return (Data("{not json at all".utf8), 200)
        default: return nil
        }
    }
    #endif

    /// GET with a status check. Throws for anything outside 200–299.
    static func data(_ request: URLRequest) async throws -> Data {
        #if DEBUG
        if simulateOffline { throw URLError(.notConnectedToInternet) }
        if let (body, status) = try await chaosReply() {
            if status >= 300 { throw URLError(.badServerResponse) }
            return body
        }
        #endif
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return data
    }

    static func data(_ url: URL) async throws -> Data { try await data(URLRequest(url: url)) }
}

/// Plain words for feed errors, for the "Couldn't load" card.
func friendlyError(_ error: Error) -> String {
    if let e = error as? URLError {
        switch e.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed: return "You’re offline. Pull down to try again when you have signal."
        case .timedOut: return "The feed took too long to answer. Try again in a moment."
        case .badServerResponse, .cannotParseResponse: return "The feed isn’t answering properly right now."
        default: break
        }
    }
    if error is DecodingError { return "The feed changed its format. We’ll fix it in an update." }
    if let e = error as? LocalizedError, let d = e.errorDescription { return d }
    return "Something went wrong. Try again."
}

/// Season start year (2026-27 → 2026). Seasons start in July.
var currentSeason: Int {
    let c = Calendar(identifier: .gregorian).dateComponents([.year, .month], from: Date())
    return (c.month ?? 1) >= 7 ? (c.year ?? 2026) : (c.year ?? 2026) - 1
}
