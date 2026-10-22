import Foundation

enum GitHubError: LocalizedError {
    case unauthorized, notFound, offline, invalidURL
    case rateLimited(resetAt: Date?)
    case http(Int, String)
    case network(String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .unauthorized: return "Your GitHub session is no longer valid. Please sign in again."
        case .notFound: return "GitHub couldn't find that resource, or you don't have access to it."
        case .offline: return "You appear to be offline."
        case .invalidURL: return "Invalid request."
        case .rateLimited(let reset):
            if let reset { return "GitHub rate limit reached. Try again \(reset.formatted(.relative(presentation: .named)))." }
            return "GitHub rate limit reached. Try again shortly."
        case .http(let code, let msg): return "GitHub returned an error (\(code)): \(msg)"
        case .network(let msg): return "Network error: \(msg)"
        case .decoding(let msg): return "Unexpected response from GitHub: \(msg)"
        }
    }
    var isUnauthorized: Bool { if case .unauthorized = self { return true } else { return false } }
}

final class GitHubClient: @unchecked Sendable {
    static let base = URL(string: "https://api.github.com")!

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private let session: URLSession
    private let token: @Sendable () -> String?

    init(session: URLSession = .shared, token: @escaping @Sendable () -> String?) {
        self.session = session
        self.token = token
    }

    func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        var comps = URLComponents(url: Self.base.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        comps?.queryItems = query.isEmpty ? nil : query
        guard let url = comps?.url else { throw GitHubError.invalidURL }

        var req = URLRequest(url: url, timeoutInterval: 20)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        if let token = token(), !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch let e as URLError {
            if e.code == .cancelled { throw CancellationError() }
            let offline: [URLError.Code] = [.notConnectedToInternet, .networkConnectionLost, .timedOut,
                                            .cannotConnectToHost, .cannotFindHost, .dataNotAllowed,
                                            .internationalRoamingOff]
            throw offline.contains(e.code) ? GitHubError.offline : GitHubError.network(e.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else { throw GitHubError.network("No response") }
        switch http.statusCode {
        case 200..<300:
            do { return try Self.decoder.decode(T.self, from: data) }
            catch { throw GitHubError.decoding(String(describing: error)) }
        case 401:
            throw GitHubError.unauthorized
        case 403, 429:
            if http.value(forHTTPHeaderField: "x-ratelimit-remaining") == "0" || http.statusCode == 429 {
                let reset = http.value(forHTTPHeaderField: "x-ratelimit-reset")
                    .flatMap(TimeInterval.init).map(Date.init(timeIntervalSince1970:))
                throw GitHubError.rateLimited(resetAt: reset)
            }
            throw GitHubError.http(http.statusCode, Self.message(from: data))
        case 404:
            throw GitHubError.notFound
        default:
            throw GitHubError.http(http.statusCode, Self.message(from: data))
        }
    }

    private static func message(from data: Data) -> String {
        struct Msg: Decodable { let message: String }
        return (try? decoder.decode(Msg.self, from: data))?.message ?? "Unknown error"
    }

    // MARK: Endpoints

    func currentUser() async throws -> GHUser { try await get("/user") }

    func searchIssues(_ q: String, sort: String = "updated", perPage: Int = 50) async throws -> [IssueItem] {
        let r: SearchResponse<IssueItem> = try await get("/search/issues", query: [
            .init(name: "q", value: q), .init(name: "sort", value: sort),
            .init(name: "order", value: "desc"), .init(name: "per_page", value: String(perPage))])
        return r.items
    }

    func myRepos() async throws -> [Repo] {
        try await get("/user/repos", query: [
            .init(name: "sort", value: "updated"), .init(name: "per_page", value: "100"),
            .init(name: "affiliation", value: "owner,collaborator,organization_member")])
    }

    func searchRepos(_ q: String) async throws -> [Repo] {
        let r: RepoSearchResponse = try await get("/search/repositories", query: [
            .init(name: "q", value: q), .init(name: "per_page", value: "30")])
        return r.items
    }

    func repo(_ fullName: String) async throws -> Repo { try await get("/repos/\(fullName)") }

    func pullRequest(repo: String, number: Int) async throws -> PullDetail {
        try await get("/repos/\(repo)/pulls/\(number)")
    }

    func reviews(repo: String, number: Int) async throws -> [PRReview] {
        try await get("/repos/\(repo)/pulls/\(number)/reviews", query: [.init(name: "per_page", value: "100")])
    }
}
