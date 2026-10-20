import XCTest
import SwiftData
@testable import PRPulse

final class ReviewStatusTests: XCTestCase {
    private func user(_ n: String) -> GHUser { GHUser(login: n, avatarUrl: nil, htmlUrl: nil) }
    private func review(_ id: Int, _ u: String, _ state: String, _ t: TimeInterval) -> PRReview {
        PRReview(id: id, user: user(u), state: state, submittedAt: Date(timeIntervalSince1970: t))
    }

    func testChangesRequestedWins() {
        let s = ReviewStatus.compute(reviews: [review(1, "a", "APPROVED", 1), review(2, "b", "CHANGES_REQUESTED", 2)], requested: [])
        XCTAssertEqual(s, .changesRequested)
    }
    func testLaterApprovalOverridesEarlierChangeRequestFromSameUser() {
        let s = ReviewStatus.compute(reviews: [review(1, "a", "CHANGES_REQUESTED", 1), review(2, "a", "APPROVED", 2)], requested: [])
        XCTAssertEqual(s, .approved)
    }
    func testCommentDoesNotOverrideApproval() {
        let s = ReviewStatus.compute(reviews: [review(1, "a", "APPROVED", 1), review(2, "a", "COMMENTED", 2)], requested: [])
        XCTAssertEqual(s, .approved)
    }
    func testDismissedReviewIsIgnored() {
        let s = ReviewStatus.compute(reviews: [review(1, "a", "CHANGES_REQUESTED", 1), review(2, "a", "DISMISSED", 2)], requested: [user("b")])
        XCTAssertEqual(s, .reviewRequired)
    }
    func testNoReviews() {
        XCTAssertEqual(ReviewStatus.compute(reviews: [], requested: []), .none)
    }
}

final class QueryBuilderTests: XCTestCase {
    func testMergedAuthored() {
        XCTAssertEqual(SearchQueryBuilder.pullRequests(scope: .authored, status: .merged),
                       "is:pr author:@me is:merged archived:false")
    }
    func testClosedExcludesMerged() {
        XCTAssertTrue(SearchQueryBuilder.pullRequests(scope: .involved, status: .closed).contains("is:closed is:unmerged"))
    }
    func testReviewRequested() {
        XCTAssertTrue(SearchQueryBuilder.pullRequests(scope: .reviewRequested, status: .open).contains("review-requested:@me"))
    }
}

final class DecodingTests: XCTestCase {
    func testIssueItemDecodesPullRequestFromSearchPayload() throws {
        let json = """
        {"total_count":1,"items":[{"id":1,"number":42,"title":"Fix bug","html_url":"https://github.com/o/r/pull/42",
        "state":"closed","repository_url":"https://api.github.com/repos/o/r",
        "user":{"login":"octo","avatar_url":null,"html_url":null},
        "labels":[{"id":9,"name":"bug","color":"d73a4a"}],
        "created_at":"2024-01-01T00:00:00Z","updated_at":"2024-01-02T00:00:00Z",
        "draft":false,"comments":3,"pull_request":{"merged_at":"2024-01-02T00:00:00Z"}}]}
        """.data(using: .utf8)!
        let r = try GitHubClient.decoder.decode(SearchResponse<IssueItem>.self, from: json)
        let item = try XCTUnwrap(r.items.first)
        XCTAssertEqual(item.repoFullName, "o/r")
        XCTAssertEqual(item.kind, .pullMerged)
    }
}

@MainActor
final class LocalCacheTests: XCTestCase {
    func testRoundTripAndOverwrite() throws {
        let container = try ModelContainer(for: CacheEntry.self, BookmarkedRepo.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let cache = LocalCache(context: container.mainContext)
        cache.save(["a", "b"], key: "k")
        cache.save(["c"], key: "k")
        let hit = try XCTUnwrap(cache.load([String].self, key: "k"))
        XCTAssertEqual(hit.value, ["c"])
        cache.clear()
        XCTAssertNil(cache.load([String].self, key: "k"))
    }
}

@MainActor
final class RouterTests: XCTestCase {
    func testDeepLinks() {
        let r = Router()
        r.handle(URL(string: "prpulse://reviews")!)
        XCTAssertEqual(r.tab, .pulls); XCTAssertEqual(r.pullScope, .reviewRequested)
        r.handle(URL(string: "prpulse://repo/apple/swift")!)
        XCTAssertEqual(r.tab, .repos); XCTAssertEqual(r.repoRoute?.fullName, "apple/swift")
        r.handle(URL(string: "prpulse://bookmarks")!)
        XCTAssertTrue(r.showBookmarksOnly)
    }
}
