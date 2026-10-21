import SwiftUI
import SwiftData

struct RepoListView: View {
    @Environment(AppEnvironment.self) private var env
    @Query(sort: \BookmarkedRepo.addedAt, order: .reverse) private var bookmarks: [BookmarkedRepo]
    @State private var vm: RepoListViewModel
    private let repository: GitHubRepository

    init(repository: GitHubRepository) {
        self.repository = repository
        _vm = State(initialValue: RepoListViewModel(repository: repository))
    }

    var body: some View {
        @Bindable var router = env.router
        NavigationStack {
            VStack(spacing: 0) {
                if !router.showBookmarksOnly {
                    Picker("Scope", selection: $vm.scope) {
                        ForEach(RepoScope.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented).padding(.horizontal).padding(.vertical, 8)
                }
                content
            }
            .navigationTitle(router.showBookmarksOnly ? "Bookmarks" : "Repositories")
            .searchable(text: $vm.query, prompt: vm.scope == .mine ? "Filter your repositories" : "Search all of GitHub")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Toggle(isOn: $router.showBookmarksOnly) { Label("Bookmarks", systemImage: "bookmark") }
                        .toggleStyle(.button)
                }
            }
            .navigationDestination(for: Repo.self) { RepoDetailView(fullName: $0.fullName, preloaded: $0) }
            .navigationDestination(item: $router.repoRoute) { RepoDetailView(fullName: $0.fullName, preloaded: nil) }
        }
        .task(id: "\(vm.scope.rawValue)|\(vm.query)|\(env.auth.isAuthenticated)") {
            switch vm.scope {
            case .mine: if env.auth.isAuthenticated { await vm.loadMine() } else { vm.repos = []; vm.phase = .loaded }
            case .search: await vm.searchPublic()
            }
        }
    }

    @ViewBuilder private var content: some View {
        if env.router.showBookmarksOnly {
            let q = vm.query.lowercased()
            let items = bookmarks.map(\.asRepo).filter { q.isEmpty || $0.fullName.lowercased().contains(q) }
            if items.isEmpty {
                ContentUnavailableView("No bookmarks yet", systemImage: "bookmark",
                                       description: Text("Tap the bookmark icon on any repository to save it here."))
                    .frame(maxHeight: .infinity)
            } else {
                List(items) { repo in
                    NavigationLink(value: repo) { RepoRow(repo: repo, isBookmarked: true) { repository.toggleBookmark(repo) } }
                }.listStyle(.plain)
            }
        } else {
            switch vm.phase {
            case .loading where vm.repos.isEmpty: ProgressView().frame(maxHeight: .infinity)
            case .failed(let msg): ErrorStateView(message: msg) { Task { vm.scope == .mine ? await vm.loadMine() : await vm.searchPublic() } }
            default:
                List {
                    if vm.scope == .mine && !env.auth.isAuthenticated {
                        Text("Sign in from the Settings tab to browse your repositories, or use “Search GitHub” for public repositories.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    if vm.fromCache || (!env.network.isOnline && vm.scope == .mine) {
                        Section { OfflineBanner(fetchedAt: vm.fetchedAt, isOffline: !env.network.isOnline, error: vm.refreshError) }
                    }
                    if vm.scope == .search && vm.query.count < 2 {
                        ContentUnavailableView("Search GitHub", systemImage: "magnifyingglass",
                                               description: Text("Type at least two characters to search public repositories."))
                            .listRowSeparator(.hidden)
                    } else if vm.visible.isEmpty && vm.phase == .loaded && env.auth.isAuthenticated || (vm.visible.isEmpty && vm.scope == .search && vm.phase == .loaded) {
                        ContentUnavailableView.search(text: vm.query).listRowSeparator(.hidden)
                    }
                    ForEach(vm.visible) { repo in
                        NavigationLink(value: repo) {
                            RepoRow(repo: repo, isBookmarked: bookmarks.contains { $0.fullName == repo.fullName }) {
                                repository.toggleBookmark(repo)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .refreshable { vm.scope == .mine ? await vm.loadMine() : await vm.searchPublic() }
            }
        }
    }
}

struct RepoDetailView: View {
    let fullName: String
    let preloaded: Repo?
    @Environment(AppEnvironment.self) private var env
    @Query private var bookmarks: [BookmarkedRepo]
    @State private var bundle: Loaded<RepoBundle>?
    @State private var error: String?

    private var repo: Repo? {
        bundle?.value.repo ?? preloaded ?? bookmarks.first { $0.fullName == fullName }?.asRepo
    }

    var body: some View {
        List {
            if let b = bundle, b.fromCache || !env.network.isOnline {
                Section { OfflineBanner(fetchedAt: b.fetchedAt, isOffline: !env.network.isOnline, error: b.errorMessage) }
            }
            if let repo {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(repo.fullName).font(.title3.weight(.semibold))
                        if let d = repo.description { Text(d).foregroundStyle(.secondary) }
                    }
                    LabeledContent("Language", value: repo.language ?? "—")
                    LabeledContent("Stars", value: "\(repo.stargazersCount)")
                    LabeledContent("Open issues", value: "\(repo.openIssuesCount)")
                    if let u = repo.updatedAt { LabeledContent("Updated", value: u.formatted(.relative(presentation: .named))) }
                    Link(destination: repo.htmlUrl) { Label("Open on GitHub", systemImage: "safari") }
                }
                Section("Open pull requests") {
                    if let pulls = bundle?.value.openPulls {
                        if pulls.isEmpty { Text("No open pull requests.").foregroundStyle(.secondary) }
                        ForEach(pulls) { NavigationLink(value: $0) { IssueRow(item: $0) } }
                    } else if error == nil {
                        ProgressView()
                    } else {
                        Text(error ?? "").font(.footnote).foregroundStyle(.secondary)
                    }
                }
            } else if let error {
                ErrorStateView(message: error) { Task { await load() } }
            } else {
                ProgressView()
            }
        }
        .navigationTitle(repo?.name ?? fullName)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: IssueItem.self) { PRDetailView(item: $0) }
        .toolbar {
            if let repo {
                ToolbarItem(placement: .topBarTrailing) {
                    let saved = bookmarks.contains { $0.fullName == repo.fullName }
                    Button { env.repository.toggleBookmark(repo) } label: {
                        Image(systemName: saved ? "bookmark.fill" : "bookmark")
                    }
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        do { bundle = try await env.repository.repoDetail(fullName: fullName); error = nil }
        catch is CancellationError {}
        catch { self.error = error.localizedDescription }
    }
}

struct SettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var confirmSignOut = false
    @State private var cleared = false

    var body: some View {
        NavigationStack {
            List {
                Section("Account") {
                    if env.auth.isAuthenticated {
                        HStack(spacing: 12) {
                            AsyncImage(url: env.auth.user?.avatarUrl) { $0.resizable() } placeholder: { Color.gray.opacity(0.2) }
                                .frame(width: 44, height: 44).clipShape(Circle())
                            VStack(alignment: .leading) {
                                Text(env.auth.user?.login ?? env.auth.accountKey).font(.headline)
                                Text("Signed in · read-only access").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Button("Sign out", role: .destructive) { confirmSignOut = true }
                    } else {
                        LoginView()
                    }
                }
                Section("Data") {
                    LabeledContent("Network", value: env.network.isOnline ? "Online" : "Offline")
                    Button(cleared ? "Cache cleared" : "Clear cached data") {
                        env.repository.clearCache(); cleared = true
                    }
                    Text("Bookmarks are kept when you clear the cache.").font(.caption).foregroundStyle(.secondary)
                }
                Section("About") {
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    Text("PR Pulse never approves, merges or comments on pull requests.").font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog("Sign out of GitHub?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) { env.signOut() }
            } message: { Text("Your token and cached data will be removed from this device.") }
        }
    }
}
