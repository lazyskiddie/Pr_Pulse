import SwiftUI

struct OfflineBanner: View {
    let fetchedAt: Date?
    let isOffline: Bool
    let error: String?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isOffline ? "wifi.slash" : "exclamationmark.triangle.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(isOffline ? "You're offline" : "Couldn't refresh").font(.subheadline.weight(.semibold))
                Text("Showing saved data\(fetchedAt.map { " from " + $0.formatted(.relative(presentation: .named)) } ?? ""). It may be out of date.")
                    .font(.caption).foregroundStyle(.secondary)
                if !isOffline, let error { Text(error).font(.caption2).foregroundStyle(.secondary) }
            }
        }
        .padding(.vertical, 2)
    }
}

struct ErrorStateView: View {
    let message: String
    let retry: () -> Void
    var body: some View {
        ContentUnavailableView {
            Label("Something went wrong", systemImage: "exclamationmark.triangle")
        } description: { Text(message) } actions: {
            Button("Try again", action: retry).buttonStyle(.borderedProminent)
        }
    }
}

struct StatusBadge: View {
    let kind: IssueItem.Kind
    var body: some View {
        let (icon, color, text): (String, Color, String) = {
            switch kind {
            case .pullOpen: return ("arrow.triangle.pull", .green, "Open")
            case .pullDraft: return ("arrow.triangle.pull", .gray, "Draft")
            case .pullMerged: return ("arrow.triangle.merge", .purple, "Merged")
            case .pullClosed: return ("xmark.circle", .red, "Closed")
            case .issueOpen: return ("circle.dotted", .green, "Open")
            case .issueClosed: return ("checkmark.circle", .purple, "Closed")
            }
        }()
        Label(text, systemImage: icon)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}

struct LabelChip: View {
    let label: GHLabel
    var body: some View {
        Text(label.name)
            .font(.caption2)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Color(hex: label.color).opacity(0.25), in: Capsule())
            .overlay(Capsule().stroke(Color(hex: label.color).opacity(0.6), lineWidth: 0.5))
            .lineLimit(1)
    }
}

struct IssueRow: View {
    let item: IssueItem
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                StatusBadge(kind: item.kind)
                Text(item.repoFullName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Text("#\(item.number)").font(.caption).foregroundStyle(.secondary)
            }
            Text(item.title).font(.subheadline.weight(.semibold)).lineLimit(2)
            HStack(spacing: 4) {
                Text("by \(item.user.login)")
                Text("·")
                Text(item.updatedAt.formatted(.relative(presentation: .named)))
                if item.comments > 0 { Text("·"); Label("\(item.comments)", systemImage: "bubble.left") .labelStyle(.titleAndIcon) }
            }
            .font(.caption).foregroundStyle(.secondary)
            if !item.labels.isEmpty {
                HStack(spacing: 4) { ForEach(item.labels.prefix(4)) { LabelChip(label: $0) } }
            }
        }
        .padding(.vertical, 2)
    }
}

/// PRs navigate to the in-app detail; issues open on GitHub.
struct WorkItemLink: View {
    let item: IssueItem
    var body: some View {
        if item.isPullRequest {
            NavigationLink(value: item) { IssueRow(item: item) }
        } else {
            Link(destination: item.htmlUrl) { IssueRow(item: item) }.tint(.primary)
        }
    }
}

struct RepoRow: View {
    let repo: Repo
    let isBookmarked: Bool
    let toggle: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AsyncImage(url: repo.owner.avatarUrl) { $0.resizable() } placeholder: { Color.gray.opacity(0.2) }
                .frame(width: 34, height: 34).clipShape(Circle())
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(repo.fullName).font(.subheadline.weight(.semibold)).lineLimit(1)
                    if repo.isPrivate == true { Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.secondary) }
                }
                if let d = repo.description, !d.isEmpty {
                    Text(d).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                HStack(spacing: 10) {
                    if let l = repo.language { Label(l, systemImage: "chevron.left.forwardslash.chevron.right") }
                    Label("\(repo.stargazersCount)", systemImage: "star")
                    Label("\(repo.openIssuesCount)", systemImage: "exclamationmark.circle")
                }
                .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button(action: toggle) {
                Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                    .foregroundStyle(isBookmarked ? Color.accentColor : .secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(isBookmarked ? "Remove bookmark" : "Add bookmark")
        }
    }
}

struct LoginView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var token = ""

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.triangle.pull").font(.system(size: 44)).foregroundStyle(.tint)
            Text("Sign in to PR Pulse").font(.title2.bold())
            Text("Connect GitHub to see your pull requests, review requests and assigned issues. PR Pulse is read-only: it never approves, merges or comments.")
                .font(.subheadline).multilineTextAlignment(.center).foregroundStyle(.secondary)

            Button {
                Task { await env.auth.signInWithGitHub() }
            } label: {
                Label("Continue with GitHub", systemImage: "person.badge.key").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .disabled(env.auth.isBusy || !Config.isOAuthConfigured)

            if !Config.isOAuthConfigured {
                Text("Web sign-in isn't configured yet (set Config.githubClientID and Config.tokenExchangeURL). You can still sign in with a token below.")
                    .font(.caption).foregroundStyle(.orange).multilineTextAlignment(.center)
            }

            DisclosureGroup("Use a personal access token") {
                VStack(alignment: .leading, spacing: 8) {
                    SecureField("github_pat_… or ghp_…", text: $token)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                    Text("Stored only in your device Keychain. Read-only access is enough.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Sign in with token") { Task { await env.auth.signIn(withToken: token) } }
                        .buttonStyle(.bordered)
                        .disabled(token.trimmingCharacters(in: .whitespaces).isEmpty || env.auth.isBusy)
                }
                .padding(.top, 6)
            }

            if env.auth.isBusy { ProgressView() }
            if let e = env.auth.errorMessage { Text(e).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center) }
        }
        .padding()
    }
}
