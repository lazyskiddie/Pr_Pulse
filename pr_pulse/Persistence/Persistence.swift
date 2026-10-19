import Foundation
import SwiftData

@Model
final class CacheEntry {
    @Attribute(.unique) var key: String
    var data: Data
    var updatedAt: Date
    init(key: String, data: Data, updatedAt: Date = .now) {
        self.key = key; self.data = data; self.updatedAt = updatedAt
    }
}

@Model
final class BookmarkedRepo {
    @Attribute(.unique) var fullName: String
    var name: String
    var summary: String?
    var language: String?
    var stars: Int
    var openIssues: Int
    var htmlURL: String
    var ownerLogin: String
    var ownerAvatar: String?
    var addedAt: Date

    init(repo: Repo) {
        fullName = repo.fullName; name = repo.name; summary = repo.description
        language = repo.language; stars = repo.stargazersCount; openIssues = repo.openIssuesCount
        htmlURL = repo.htmlUrl.absoluteString; ownerLogin = repo.owner.login
        ownerAvatar = repo.owner.avatarUrl?.absoluteString; addedAt = .now
    }

    var asRepo: Repo {
        Repo(name: name, fullName: fullName, description: summary, language: language,
             stargazersCount: stars, openIssuesCount: openIssues,
             htmlUrl: URL(string: htmlURL) ?? URL(string: "https://github.com/\(fullName)")!,
             owner: GHUser(login: ownerLogin, avatarUrl: ownerAvatar.flatMap(URL.init), htmlUrl: nil),
             updatedAt: nil, isPrivate: nil)
    }
}

/// Stores the last successful API results as JSON blobs in SwiftData.
@MainActor
final class LocalCache {
    private let context: ModelContext

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e
    }()
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }()

    init(context: ModelContext) { self.context = context }

    func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? Self.encoder.encode(value) else { return }
        let descriptor = FetchDescriptor<CacheEntry>(predicate: #Predicate { $0.key == key })
        if let existing = try? context.fetch(descriptor).first {
            existing.data = data; existing.updatedAt = .now
        } else {
            context.insert(CacheEntry(key: key, data: data))
        }
        try? context.save()
    }

    func load<T: Decodable>(_ type: T.Type, key: String) -> (value: T, date: Date)? {
        let descriptor = FetchDescriptor<CacheEntry>(predicate: #Predicate { $0.key == key })
        guard let entry = try? context.fetch(descriptor).first,
              let value = try? Self.decoder.decode(T.self, from: entry.data) else { return nil }
        return (value, entry.updatedAt)
    }

    /// Removes cached API results (bookmarks are kept).
    func clear() {
        try? context.delete(model: CacheEntry.self)
        try? context.save()
    }
}
