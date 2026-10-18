import Foundation

enum Config {
    /// Client ID of your GitHub App (or OAuth App). The client ID is public; the SECRET lives only in the Cloudflare Worker.
    static let githubClientID = "YOUR_GITHUB_CLIENT_ID"
    /// URL of the deployed Cloudflare Worker (see /worker).
    static let tokenExchangeURL = URL(string: "https://YOUR-WORKER.workers.dev")!
    static let callbackScheme = "prpulse"
    static var redirectURI: String { "\(callbackScheme)://auth" }

    static var isOAuthConfigured: Bool {
        !githubClientID.hasPrefix("YOUR_") && !tokenExchangeURL.absoluteString.contains("YOUR-")
    }
}
