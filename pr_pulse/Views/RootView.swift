import SwiftUI

struct RootView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        @Bindable var router = env.router
        TabView(selection: $router.tab) {
            DashboardView(repository: env.repository)
                .tabItem { Label("My Work", systemImage: "rectangle.stack.person.crop") }
                .tag(Router.Tab.dashboard)
            PRListView(repository: env.repository)
                .tabItem { Label("Pull Requests", systemImage: "arrow.triangle.pull") }
                .tag(Router.Tab.pulls)
            RepoListView(repository: env.repository)
                .tabItem { Label("Repositories", systemImage: "books.vertical") }
                .tag(Router.Tab.repos)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gear") }
                .tag(Router.Tab.settings)
        }
        .task { await env.start() }
    }
}
