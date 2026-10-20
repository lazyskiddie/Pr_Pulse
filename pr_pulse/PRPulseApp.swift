import SwiftUI
import SwiftData

@main
struct PRPulseApp: App {
    private let container: ModelContainer
    @State private var env: AppEnvironment

    init() {
        let c = try! ModelContainer(for: CacheEntry.self, BookmarkedRepo.self)
        container = c
        _env = State(initialValue: AppEnvironment(container: c))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(env)
                .modelContainer(container)
                .onOpenURL { env.router.handle($0) }
        }
    }
}
