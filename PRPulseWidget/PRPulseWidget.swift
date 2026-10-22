import WidgetKit
import SwiftUI
import AppIntents

enum WidgetMode: String, AppEnum {
    case reviews, repos
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Content")
    static var caseDisplayRepresentations: [WidgetMode: DisplayRepresentation] = [
        .reviews: "Review queue", .repos: "Saved repositories"
    ]
}

struct SelectModeIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "PR Pulse"
    static var description = IntentDescription("Choose what the widget shows.")
    @Parameter(title: "Show", default: .reviews) var mode: WidgetMode
}

struct PulseEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    let mode: WidgetMode
}

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> PulseEntry {
        PulseEntry(date: .now, snapshot: .empty, mode: .reviews)
    }
    func snapshot(for configuration: SelectModeIntent, in context: Context) async -> PulseEntry {
        PulseEntry(date: .now, snapshot: WidgetStore.read(), mode: configuration.mode)
    }
    func timeline(for configuration: SelectModeIntent, in context: Context) async -> Timeline<PulseEntry> {
        let entry = PulseEntry(date: .now, snapshot: WidgetStore.read(), mode: configuration.mode)
        return Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(30 * 60)))
    }
}

struct PRPulseWidgetView: View {
    let entry: PulseEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch entry.mode {
            case .reviews: reviews
            case .repos: repos
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var reviews: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Review queue", systemImage: "eye").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if entry.snapshot.signedIn {
                Text("\(entry.snapshot.reviewCount)").font(.system(size: 48, weight: .bold, design: .rounded))
                Text(entry.snapshot.reviewCount == 1 ? "PR awaiting your review" : "PRs awaiting your review")
                    .font(.caption).foregroundStyle(.secondary)
                if let u = entry.snapshot.updatedAt {
                    Text("Updated \(u.formatted(.relative(presentation: .named)))").font(.caption2).foregroundStyle(.tertiary)
                }
            } else {
                Text("Sign in to PR Pulse").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(URL(string: "prpulse://reviews"))
    }

    private var repos: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Saved repositories", systemImage: "bookmark.fill").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if entry.snapshot.bookmarks.isEmpty {
                Text("Bookmark a repository in the app to see it here.").font(.footnote).foregroundStyle(.secondary)
            } else {
                ForEach(entry.snapshot.bookmarks.prefix(family == .systemSmall ? 3 : 4), id: \.self) { name in
                    Link(destination: URL(string: "prpulse://repo/\(name)")!) {
                        Text(name).font(.footnote.weight(.medium)).lineLimit(1)
                    }
                    .tint(.primary)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(URL(string: "prpulse://bookmarks"))
    }
}

struct PRPulseWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "PRPulseWidget", intent: SelectModeIntent.self, provider: Provider()) {
            PRPulseWidgetView(entry: $0)
        }
        .configurationDisplayName("PR Pulse")
        .description("Your review queue or saved repositories.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct PRPulseWidgetBundle: WidgetBundle {
    var body: some Widget { PRPulseWidget() }
}
