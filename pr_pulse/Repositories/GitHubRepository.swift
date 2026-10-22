import Foundation
import SwiftData
import WidgetKit

struct Loaded<T> {
    var value: T
    var fetchedAt: Date
    var fromCache: Bool
    /// Set when live data failed and cached data was served instead.
    var errorMessage: String?
}

/// Single entry point for data. Tries the live API, caches on success, falls back to the cache on failure.
@MainActor
final class GitHubRepository {
    private let client: GitHubClient
    let cache: LocalCache
    private let context: ModelContext
    private let account: () -> String

    init(client: GitHubClient, context: ModelContext, account: @escaping () -> String) {
        self.client = client
        self.context = context
        self.cache = LocalCache(context: context)
        self.account = account
    }

    private func cached<T: Codable>(_ key: String, _ fetch: () async throws -> T) async throws -> Loaded<T> {
        let fullKey = "\(account()).\(key)"
        do {
            let value = try await fetch()
            cache.save(value, key: fullKey)
            return Loaded(value: value, fetchedAt: .now, fromCache: false, errorMessage: nil)
        } catch is CancellationError {
            throw CancellationError()
        } catch let e as GitHubError where e.isUnauthorized {
            throw e
        } catch {
            if let hit = cache.load(T.self, key: fullKey) {
                return Loaded(value: hit.value, fetchedAt: hit.date, fromCache: true, errorMessage: error.localizedDescription)
            }
            throw error
        }
    }

    // MARK: My Work

    func dashboard() async throws -> Loaded<DashboardData> {
        let result = try await cached("dashboard") { [client] in
            async let reviews = client.searchIssues("is:pr is:open review-requested:@me archived:false")
            async let mine = client.searchIssues("is:pr is:open author:@me archived:false")
            async let issues = client.searchIssues("is:issue is:open assignee:@me archived:false")
            async let repos = client.myRepos()
            return try await DashboardData(reviewRequests: reviews, myPulls: mine, assignedIssues: issues,
                                           recentRepos: Array(repos.prefix(8)))
        }
        if !result.fromCache {
            WidgetStore.update {
                $0.reviewCount = result.value.reviewRequests.count
                $0.updatedAt = result.fetchedAt
                $0.signedIn = true
            }
            WidgetCenter.shared.reloadAllTimelines()
        }
        return result
    }

    // MARK: Pull requests

    func pullRequests(scope: PRScope, status: PRStatus, sort: PRSort) async throws -> Loaded<[IssueItem]> {
        let q = SearchQueryBuilder.pullRequests(scope: scope, status: status)
        return try await cached("prs.\(scope.rawValue).\(status.rawValue).\(sort.rawValue)") { [client] in
            try await client.searchIssues(q, sort: sort.apiValue, perPage: 50)
        }
    }

    func prDetail(repo: String, number: Int) async throws -> Loaded<PRBundle> {
        try await cached("pr.\(repo)#\(number)") { [client] in
            async let detail = client.pullRequest(repo: repo, number: number)
            async let reviews = client.reviews(repo: repo, number: number)
            let (d, r) = try await (detail, reviews)
            return PRBundle(detail: d, reviews: r,
                            status: ReviewStatus.compute(reviews: r, requested: d.requestedReviewers ?? []))
        }
    }

    // MARK: Repositories

    func myRepos() async throws -> Loaded<[Repo]> {
        try await cached("repos.mine") { [client] in try await client.myRepos() }
    }

    func searchPublicRepos(_ query: String) async throws -> [Repo] {
        try await client.searchRepos(query)
    }

    func repoDetail(fullName: String) async throws -> Loaded<RepoBundle> {
        try await cached("repo.\(fullName)") { [client] in
            async let repo = client.repo(fullName)
            async let pulls = client.searchIssues("repo:\(fullName) is:pr is:open", perPage: 30)
            return try await RepoBundle(repo: repo, openPulls: pulls)
        }
    }

    // MARK: Bookmarks

    func isBookmarked(_ fullName: String) -> Bool {
        let d = FetchDescriptor<BookmarkedRepo>(predicate: #Predicate { $0.fullName == fullName })
        return ((try? context.fetchCount(d)) ?? 0) > 0
    }

    func toggleBookmark(_ repo: Repo) {
        let name = repo.fullName
        let d = FetchDescriptor<BookmarkedRepo>(predicate: #Predicate { $0.fullName == name })
        if let existing = try? context.fetch(d).first {
            context.delete(existing)
        } else {
            context.insert(BookmarkedRepo(repo: repo))
        }
        try? context.save()
        syncWidgetBookmarks()
    }

    func syncWidgetBookmarks() {
        let all = (try? context.fetch(FetchDescriptor<BookmarkedRepo>(sortBy: [SortDescriptor(\.addedAt, order: .reverse)]))) ?? []
        WidgetStore.update { $0.bookmarks = all.map(\.fullName) }
        WidgetCenter.shared.reloadAllTimelines()
    }

    func clearCache() { cache.clear() }
}
