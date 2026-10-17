import SwiftUI

struct PRListView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var vm: PRListViewModel

    init(repository: GitHubRepository) {
        _vm = State(initialValue: PRListViewModel(repository: repository))
    }

    var body: some View {
        NavigationStack {
            Group {
                if !env.auth.isAuthenticated {
                    ScrollView { LoginView() }
                } else {
                    VStack(spacing: 0) {
                        Picker("Status", selection: $vm.status) {
                            ForEach(PRStatus.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented).padding(.horizontal).padding(.vertical, 8)
                        content
                    }
                }
            }
            .navigationTitle("Pull Requests")
            .searchable(text: $vm.searchText, prompt: "Filter by title, repo, author or label")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Show", selection: $vm.scope) { ForEach(PRScope.allCases) { Text($0.rawValue).tag($0) } }
                        Picker("Sort by", selection: $vm.sort) { ForEach(PRSort.allCases) { Text($0.rawValue).tag($0) } }
                    } label: { Label("Filters", systemImage: "line.3.horizontal.decrease.circle") }
                }
            }
            .navigationDestination(for: IssueItem.self) { PRDetailView(item: $0) }
            .safeAreaInset(edge: .top, spacing: 0) {
                if env.auth.isAuthenticated {
                    Text("\(vm.scope.rawValue) · \(vm.sort.rawValue)")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal).padding(.top, 4)
                }
            }
        }
        .task(id: "\(vm.queryKey)|\(env.auth.isAuthenticated)") {
            applyDeepLink()
            if env.auth.isAuthenticated { await vm.load() }
        }
        .onChange(of: env.router.pullScope) { _, _ in applyDeepLink() }
    }

    private func applyDeepLink() {
        if let scope = env.router.pullScope {
            vm.scope = scope; vm.status = .open
            env.router.pullScope = nil
        }
    }

    @ViewBuilder private var content: some View {
        switch vm.phase {
        case .idle, .loading where vm.items.isEmpty:
            ProgressView().frame(maxHeight: .infinity)
        case .failed(let msg):
            ErrorStateView(message: msg) { Task { await vm.load() } }
        default:
            List {
                if vm.fromCache || !env.network.isOnline {
                    Section { OfflineBanner(fetchedAt: vm.fetchedAt, isOffline: !env.network.isOnline, error: vm.refreshError) }
                }
                if vm.filtered.isEmpty {
                    ContentUnavailableView(vm.searchText.isEmpty ? "No \(vm.status.rawValue.lowercased()) pull requests" : "No matches",
                                           systemImage: "arrow.triangle.pull",
                                           description: Text(vm.searchText.isEmpty ? "Nothing to show for “\(vm.scope.rawValue)”." : "Try a different search."))
                        .listRowSeparator(.hidden)
                }
                ForEach(vm.filtered) { NavigationLink(value: $0) { IssueRow(item: $0) } }
            }
            .listStyle(.plain)
            .refreshable { await vm.load() }
        }
    }
}

struct PRDetailView: View {
    let item: IssueItem
    @Environment(AppEnvironment.self) private var env
    @State private var bundle: Loaded<PRBundle>?
    @State private var error: String?
    @State private var loading = true

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack { StatusBadge(kind: item.kind); Text("#\(item.number)").foregroundStyle(.secondary) }
                    Text(item.title).font(.title3.weight(.semibold))
                    Text(item.repoFullName).font(.subheadline).foregroundStyle(.secondary)
                    if !item.labels.isEmpty {
                        HStack(spacing: 4) { ForEach(item.labels.prefix(6)) { LabelChip(label: $0) } }
                    }
                }
            }

            if let b = bundle, b.fromCache || !env.network.isOnline {
                Section { OfflineBanner(fetchedAt: b.fetchedAt, isOffline: !env.network.isOnline, error: b.errorMessage) }
            }

            Section("Details") {
                row("Author", item.user.login)
                row("Updated", item.updatedAt.formatted(.relative(presentation: .named)))
                row("Created", item.createdAt.formatted(date: .abbreviated, time: .omitted))
                if let d = bundle?.value.detail {
                    row("Branches", "\(d.head.ref) → \(d.base.ref)")
                    if let s = bundle?.value.status { row("Review status", s.rawValue) }
                    if let rr = d.requestedReviewers, !rr.isEmpty { row("Requested", rr.map(\.login).joined(separator: ", ")) }
                    if let c = d.commits { row("Commits", "\(c)") }
                    if let f = d.changedFiles { row("Files changed", "\(f)") }
                    if let a = d.additions, let del = d.deletions { row("Changes", "+\(a)  −\(del)") }
                }
            }

            if loading && bundle == nil { Section { ProgressView("Loading details…") } }
            if let error, bundle == nil { Section { Text(error).font(.footnote).foregroundStyle(.secondary) } }

            if let body = bundle?.value.detail.body, !body.isEmpty {
                Section("Description") { Text(.init(String(body.prefix(1500)))).font(.callout) }
            }

            Section {
                Link(destination: item.htmlUrl) {
                    Label("Open on GitHub", systemImage: "safari").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Pull Request")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func row(_ k: String, _ v: String) -> some View {
        LabeledContent(k) { Text(v).multilineTextAlignment(.trailing) }
    }

    private func load() async {
        loading = true; defer { loading = false }
        do {
            bundle = try await env.repository.prDetail(repo: item.repoFullName, number: item.number)
            error = nil
        } catch is CancellationError {
        } catch { self.error = error.localizedDescription }
    }
}
