import Foundation
import Observation
import SwiftData

@MainActor @Observable
final class AppEnvironment {
    let client: GitHubClient
    let auth: AuthService
    let repository: GitHubRepository
    let network = NetworkMonitor()
    let router = Router()

    init(container: ModelContainer) {
        let client = GitHubClient(token: { KeychainStore.read(account: "github.token") })
        let auth = AuthService(client: client)
        self.client = client
        self.auth = auth
        self.repository = GitHubRepository(client: client, context: container.mainContext,
                                           account: { [unowned auth] in auth.accountKey })
    }

    func start() async {
        repository.syncWidgetBookmarks()
        await auth.restore()
    }

    func signOut() {
        auth.signOutLocally()
        repository.clearCache()
    }
}

@MainActor @Observable
final class Router {
    enum Tab: Hashable { case dashboard, pulls, repos, settings }
    struct RepoRoute: Hashable { let fullName: String }

    var tab: Tab = .dashboard
    var pullScope: PRScope?
    var repoRoute: RepoRoute?
    var showBookmarksOnly = false

    /// Handles `prpulse://reviews`, `prpulse://bookmarks`, `prpulse://repo/owner/name`, `prpulse://dashboard`.
    func handle(_ url: URL) {
        guard url.scheme == Config.callbackScheme else { return }
        switch url.host {
        case "reviews":
            tab = .pulls; pullScope = .reviewRequested
        case "bookmarks":
            tab = .repos; showBookmarksOnly = true
        case "repo":
            let parts = url.pathComponents.filter { $0 != "/" }
            if parts.count >= 2 { tab = .repos; repoRoute = RepoRoute(fullName: "\(parts[0])/\(parts[1])") }
        case "dashboard":
            tab = .dashboard
        default: break
        }
    }
}
