import Foundation
import AuthenticationServices
import Observation
import UIKit
import WidgetKit

@MainActor @Observable
final class AuthService: NSObject {
    private static let tokenAccount = "github.token"
    private static let loginKey = "github.login"

    var user: GHUser?
    var isAuthenticated = false
    var isBusy = false
    var errorMessage: String?

    /// Used to namespace cached data per account.
    var accountKey: String { UserDefaults.standard.string(forKey: Self.loginKey) ?? "anon" }

    @ObservationIgnored private let client: GitHubClient
    @ObservationIgnored private var webSession: ASWebAuthenticationSession?

    init(client: GitHubClient) {
        self.client = client
        super.init()
        isAuthenticated = KeychainStore.read(account: Self.tokenAccount) != nil
    }

    /// Validates the stored token on launch. Keeps the session if we are merely offline.
    func restore() async {
        guard isAuthenticated else { return }
        do {
            user = try await client.currentUser()
            if let login = user?.login { UserDefaults.standard.set(login, forKey: Self.loginKey) }
        } catch let e as GitHubError where e.isUnauthorized {
            signOutLocally()
        } catch { /* offline or transient: stay signed in, use cache */ }
    }

    // MARK: Web flow (GitHub App / OAuth App via token-exchange worker)

    func signInWithGitHub() async {
        errorMessage = nil
        isBusy = true
        defer { isBusy = false }
        do {
            let state = UUID().uuidString
            var c = URLComponents(string: "https://github.com/login/oauth/authorize")!
            c.queryItems = [
                .init(name: "client_id", value: Config.githubClientID),
                .init(name: "redirect_uri", value: Config.redirectURI),
                .init(name: "state", value: state),
                .init(name: "scope", value: "repo read:org")   // ignored by GitHub Apps
            ]
            let callback = try await authenticate(url: c.url!)
            let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
            guard items.first(where: { $0.name == "state" })?.value == state,
                  let code = items.first(where: { $0.name == "code" })?.value else {
                throw AuthError.message("Authorization was cancelled or returned an invalid response.")
            }
            let token = try await exchange(code: code)
            try await finishSignIn(token: token)
        } catch ASWebAuthenticationSessionError.canceledLogin {
            // user cancelled; no error
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Personal access token

    func signIn(withToken raw: String) async {
        errorMessage = nil
        isBusy = true
        defer { isBusy = false }
        do { try await finishSignIn(token: raw.trimmingCharacters(in: .whitespacesAndNewlines)) }
        catch { errorMessage = error.localizedDescription }
    }

    private func finishSignIn(token: String) async throws {
        KeychainStore.save(token, account: Self.tokenAccount)
        do {
            let me = try await client.currentUser()
            user = me
            UserDefaults.standard.set(me.login, forKey: Self.loginKey)
            isAuthenticated = true
        } catch {
            KeychainStore.delete(account: Self.tokenAccount)
            throw error
        }
    }

    func signOutLocally() {
        KeychainStore.delete(account: Self.tokenAccount)
        UserDefaults.standard.removeObject(forKey: Self.loginKey)
        user = nil
        isAuthenticated = false
        WidgetStore.update { $0.reviewCount = 0; $0.signedIn = false; $0.updatedAt = nil }
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: Helpers

    private enum AuthError: LocalizedError {
        case message(String)
        var errorDescription: String? { if case .message(let m) = self { return m } else { return nil } }
    }

    private func authenticate(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { cont in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: Config.callbackScheme) { url, error in
                if let url { cont.resume(returning: url) }
                else { cont.resume(throwing: error ?? AuthError.message("Sign-in failed.")) }
            }
            session.presentationContextProvider = self
            webSession = session
            if !session.start() { cont.resume(throwing: AuthError.message("Could not start sign-in.")) }
        }
    }

    private func exchange(code: String) async throws -> String {
        struct Resp: Decodable { let accessToken: String?; let error: String? }
        var req = URLRequest(url: Config.tokenExchangeURL, timeoutInterval: 20)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(["code": code, "redirect_uri": Config.redirectURI])
        let (data, _) = try await URLSession.shared.data(for: req)
        let resp = try GitHubClient.decoder.decode(Resp.self, from: data)
        guard let token = resp.accessToken else { throw AuthError.message(resp.error ?? "Token exchange failed.") }
        return token
    }
}

extension AuthService: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first(where: \.isKeyWindow) ?? ASPresentationAnchor()
        }
    }
}
