import SwiftUI

struct DashboardView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var vm: DashboardViewModel

    init(repository: GitHubRepository) {
        _vm = State(initialValue: DashboardViewModel(repository: repository))
    }

    var body: some View {
        NavigationStack {
            Group {
                if !env.auth.isAuthenticated {
                    ScrollView { LoginView() }
                } else {
                    switch vm.phase {
                    case .idle, .loading where vm.data == nil:
                        ProgressView("Loading your work…")
                    case .failed(let msg):
                        ErrorStateView(message: msg) { Task { await vm.refresh() } }
                    default:
                        list
                    }
                }
            }
            .navigationTitle("My Work")
            .navigationDestination(for: IssueItem.self) { PRDetailView(item: $0) }
            .navigationDestination(for: Repo.self) { RepoDetailView(fullName: $0.fullName, preloaded: $0) }
        }
        .task(id: env.auth.isAuthenticated) {
            if env.auth.isAuthenticated { await vm.refresh() } else { vm.reset() }
        }
    }

    @ViewBuilder private var list: some View {
        if let d = vm.data {
            List {
                if vm.fromCache || !env.network.isOnline {
                    Section { OfflineBanner(fetchedAt: vm.fetchedAt, isOffline: !env.network.isOnline, error: vm.refreshError) }
                }
                section("Review requests", icon: "eye", items: d.reviewRequests, empty: "Nothing is waiting for your review.")
                section("Your open pull requests", icon: "arrow.triangle.pull", items: d.myPulls, empty: "You have no open pull requests.")
                section("Assigned issues", icon: "exclamationmark.circle", items: d.assignedIssues, empty: "No issues are assigned to you.")
                Section {
                    if d.recentRepos.isEmpty { Text("No repositories yet.").foregroundStyle(.secondary) }
                    ForEach(d.recentRepos) { repo in
                        NavigationLink(value: repo) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(repo.fullName).font(.subheadline.weight(.semibold))
                                if let u = repo.updatedAt {
                                    Text("Updated \(u.formatted(.relative(presentation: .named)))").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } header: { Label("Recently updated repositories", systemImage: "clock") }
            }
            .refreshable { await vm.refresh() }
        }
    }

    private func section(_ title: String, icon: String, items: [IssueItem], empty: String) -> some View {
        Section {
            if items.isEmpty { Text(empty).foregroundStyle(.secondary) }
            ForEach(items) { WorkItemLink(item: $0) }
        } header: {
            Label("\(title) (\(items.count))", systemImage: icon)
        }
    }
}
