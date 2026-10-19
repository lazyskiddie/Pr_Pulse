import Foundation
import SwiftUI

struct GHUser: Codable, Hashable {
    let login: String
    let avatarUrl: URL?
    let htmlUrl: URL?
}

struct GHLabel: Codable, Hashable, Identifiable {
    let id: Int
    let name: String
    let color: String
}

struct SearchResponse<T: Codable>: Codable {
    let totalCount: Int
    let items: [T]
}

/// An item from the issue-search endpoint (covers both issues and pull requests).
struct IssueItem: Codable, Identifiable, Hashable {
    struct PRRef: Codable, Hashable { let mergedAt: Date? }

    let id: Int
    let number: Int
    let title: String
    let htmlUrl: URL
    let state: String
    let repositoryUrl: URL
    let user: GHUser
    let labels: [GHLabel]
    let createdAt: Date
    let updatedAt: Date
    let draft: Bool?
    let comments: Int
    let pullRequest: PRRef?

    var repoFullName: String { repositoryUrl.pathComponents.suffix(2).joined(separator: "/") }
    var isPullRequest: Bool { pullRequest != nil }
    var isMerged: Bool { pullRequest?.mergedAt != nil }

    enum Kind { case pullOpen, pullDraft, pullMerged, pullClosed, issueOpen, issueClosed }
    var kind: Kind {
        if isPullRequest {
            if isMerged { return .pullMerged }
            if state == "closed" { return .pullClosed }
            return draft == true ? .pullDraft : .pullOpen
        }
        return state == "closed" ? .issueClosed : .issueOpen
    }
}

struct Repo: Codable, Identifiable, Hashable {
    let name: String
    let fullName: String
    let description: String?
    let language: String?
    let stargazersCount: Int
    let openIssuesCount: Int
    let htmlUrl: URL
    let owner: GHUser
    let updatedAt: Date?
    let isPrivate: Bool?

    var id: String { fullName }

    enum CodingKeys: String, CodingKey {
        case name, fullName, description, language, stargazersCount, openIssuesCount
        case htmlUrl, owner, updatedAt
        case isPrivate = "private"
    }
}

struct RepoSearchResponse: Codable { let totalCount: Int; let items: [Repo] }

struct Branch: Codable, Hashable { let ref: String }

struct PullDetail: Codable, Hashable {
    let number: Int
    let title: String
    let body: String?
    let state: String
    let draft: Bool?
    let merged: Bool?
    let mergedAt: Date?
    let htmlUrl: URL
    let user: GHUser
    let head: Branch
    let base: Branch
    let additions: Int?
    let deletions: Int?
    let changedFiles: Int?
    let commits: Int?
    let requestedReviewers: [GHUser]?
    let updatedAt: Date
}

struct PRReview: Codable, Hashable {
    let id: Int
    let user: GHUser?
    let state: String
    let submittedAt: Date?
}

enum ReviewStatus: String, Codable {
    case approved = "Approved"
    case changesRequested = "Changes requested"
    case reviewRequired = "Review required"
    case commented = "Commented"
    case none = "No reviews yet"

    static func compute(reviews: [PRReview], requested: [GHUser]) -> ReviewStatus {
        var latest: [String: String] = [:]
        var commented = false
        let ordered = reviews.sorted { ($0.submittedAt ?? .distantPast) < ($1.submittedAt ?? .distantPast) }
        for r in ordered {
            guard let login = r.user?.login else { continue }
            switch r.state {
            case "APPROVED", "CHANGES_REQUESTED": latest[login] = r.state
            case "DISMISSED": latest[login] = nil
            case "COMMENTED": commented = true
            default: break
            }
        }
        if latest.values.contains("CHANGES_REQUESTED") { return .changesRequested }
        if latest.values.contains("APPROVED") { return .approved }
        if !requested.isEmpty { return .reviewRequired }
        return commented ? .commented : .none
    }
}

struct PRBundle: Codable {
    var detail: PullDetail
    var reviews: [PRReview]
    var status: ReviewStatus
}

struct RepoBundle: Codable {
    var repo: Repo
    var openPulls: [IssueItem]
}

struct DashboardData: Codable {
    var reviewRequests: [IssueItem]
    var myPulls: [IssueItem]
    var assignedIssues: [IssueItem]
    var recentRepos: [Repo]
}

// MARK: Filters / query building

enum PRScope: String, CaseIterable, Identifiable {
    case authored = "Authored", reviewRequested = "Review requests", involved = "Involved"
    var id: String { rawValue }
    var qualifier: String {
        switch self {
        case .authored: return "author:@me"
        case .reviewRequested: return "review-requested:@me"
        case .involved: return "involves:@me"
        }
    }
}

enum PRStatus: String, CaseIterable, Identifiable {
    case open = "Open", closed = "Closed", merged = "Merged"
    var id: String { rawValue }
    var qualifier: String {
        switch self {
        case .open: return "is:open"
        case .closed: return "is:closed is:unmerged"
        case .merged: return "is:merged"
        }
    }
}

enum PRSort: String, CaseIterable, Identifiable {
    case updated = "Recently updated", created = "Newest", comments = "Most discussed"
    var id: String { rawValue }
    var apiValue: String {
        switch self { case .updated: return "updated"; case .created: return "created"; case .comments: return "comments" }
    }
}

enum SearchQueryBuilder {
    static func pullRequests(scope: PRScope, status: PRStatus) -> String {
        "is:pr \(scope.qualifier) \(status.qualifier) archived:false"
    }
}

extension Color {
    init(hex: String) {
        var v: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&v)
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}
