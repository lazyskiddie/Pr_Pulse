import Foundation

/// Shared between the app and the widget extension (compiled into both targets).
enum AppGroup {
    static let id = "group.com.example.prpulse"
}

struct WidgetSnapshot: Codable, Equatable {
    var reviewCount: Int
    var bookmarks: [String]
    var updatedAt: Date?
    var signedIn: Bool

    static let empty = WidgetSnapshot(reviewCount: 0, bookmarks: [], updatedAt: nil, signedIn: false)
}

enum WidgetStore {
    private static let key = "widget.snapshot"
    private static var defaults: UserDefaults? { UserDefaults(suiteName: AppGroup.id) }

    static func read() -> WidgetSnapshot {
        guard let data = defaults?.data(forKey: key),
              let snap = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else { return .empty }
        return snap
    }

    static func update(_ change: (inout WidgetSnapshot) -> Void) {
        var snap = read()
        change(&snap)
        if let data = try? JSONEncoder().encode(snap) { defaults?.set(data, forKey: key) }
    }
}
