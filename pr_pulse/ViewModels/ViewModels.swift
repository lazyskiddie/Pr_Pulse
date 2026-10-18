import Foundation
import Observation

enum LoadPhase: Equatable {
    case idle, loading, loaded
    case failed(String)
}

@MainActor @Observable
final class DashboardViewModel {
    var data: DashboardData?
    var phase: LoadPhase = .idle
    var fetchedAt: Date?
    var fromCache = false
    var refreshError: String?
    @ObservationIgnored private let repository: GitHubRepository

    init(repository: GitHubRepository) { self.repository = repository }

    func refresh() async {
        if data == nil { phase = .loading }
        do {
            let l = try await repository.dashboard()
            data = l.value; fetchedAt = l.fetchedAt; fromCache = l.fromCache
            refreshError = l.errorMessage; phase = .loaded
        } catch is CancellationError {
            if data == nil { phase = .idle }
        } catch {
            if data == nil { phase = .failed(error.localizedDescription) }
            else { refreshError = error.localizedDescription }
        }
    }

    func reset() { data = nil; phase = .idle; fromCache = false; refreshError = nil }
}

@MainActor @Observable
final class PRListViewModel {
    var scope: PRScope = .authored
    var status: PRStatus = .open
    var sort: PRSort = .updated
    var searchText = ""
    var items: [IssueItem] = []
    var phase: LoadPhase = .idle
    var fetchedAt: Date?
    var fromCache = false
    var refreshError: String?
    @ObservationIgnored private let repository: GitHubRepository

    init(repository: GitHubRepository) { self.repository = repository }

    var queryKey: String { "\(scope.rawValue)|\(status.rawValue)|\(sort.rawValue)" }

    var filtered: [IssueItem] {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return items }
        return items.filter {
            $0.title.lowercased().contains(q) || $0.repoFullName.lowercased().contains(q)
                || $0.user.login.lowercased().contains(q) || $0.labels.contains { $0.name.lowercased().contains(q) }
        }
    }

    func load() async {
        phase = .loading
        do {
            let l = try await repository.pullRequests(scope: scope, status: status, sort: sort)
            items = l.value; fetchedAt = l.fetchedAt; fromCache = l.fromCache
            refreshError = l.errorMessage; phase = .loaded
        } catch is CancellationError {
        } catch {
            items = []; phase = .failed(error.localizedDescription)
        }
    }
}

enum RepoScope: String, CaseIterable, Identifiable {
    case mine = "My repositories", search = "Search GitHub"
    var id: String { rawValue }
}

@MainActor @Observable
final class RepoListViewModel {
    var scope: RepoScope = .mine
    var query = ""
    var repos: [Repo] = []
    var phase: LoadPhase = .idle
    var fetchedAt: Date?
    var fromCache = false
    var refreshError: String?
    @ObservationIgnored private let repository: GitHubRepository

    init(repository: GitHubRepository) { self.repository = repository }

    var visible: [Repo] {
        guard scope == .mine else { return repos }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return repos }
        return repos.filter { $0.fullName.lowercased().contains(q) || ($0.description ?? "").lowercased().contains(q)
            || ($0.language ?? "").lowercased().contains(q) }
    }

    func loadMine() async {
        phase = .loading
        do {
            let l = try await repository.myRepos()
            repos = l.value; fetchedAt = l.fetchedAt; fromCache = l.fromCache
            refreshError = l.errorMessage; phase = .loaded
        } catch is CancellationError {
        } catch { repos = []; phase = .failed(error.localizedDescription) }
    }

    func searchPublic() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { repos = []; phase = .idle; return }
        try? await Task.sleep(for: .milliseconds(400))   // debounce; cancelled by .task(id:)
        if Task.isCancelled { return }
        phase = .loading
        do {
            repos = try await repository.searchPublicRepos(q)
            fromCache = false; refreshError = nil; phase = .loaded
        } catch is CancellationError {
        } catch { repos = []; phase = .failed(error.localizedDescription) }
    }
}
