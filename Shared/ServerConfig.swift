import Foundation

/// Where Matchday's data server lives (see `server/README.md`).
/// Debug builds use the server running on this Mac, which the Simulator reaches at localhost.
enum ServerConfig {
    #if DEBUG
    static let defaultURL = URL(string: "http://localhost:8787")!
    #else
    /// Set this to the Cloudflare Workers address printed by `npx wrangler deploy`.
    static let defaultURL = URL(string: "https://matchday-api.example.workers.dev")!
    #endif

    /// The address in use. Debug builds can point elsewhere (a Mac on the network, say)
    /// with the launch argument `-serverURL http://192.168.1.20:8787`.
    static var baseURL: URL {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-serverURL"), i + 1 < args.count, let url = URL(string: args[i + 1]) { return url }
        #endif
        return defaultURL
    }
}
