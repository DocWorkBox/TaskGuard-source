import CodexProcessManagerCore
import SwiftUI

struct GroupListView: View {
    let groups: [ServiceGroup]
    @Binding var selectedGroupID: ServiceGroup.ID?

    var body: some View {
        List(groups, selection: $selectedGroupID) { group in
            GroupRowView(group: group)
                .tag(group.id)
        }
        .overlay {
            if groups.isEmpty {
                ContentUnavailableView(
                    "没有匹配的服务",
                    systemImage: "checkmark.circle",
                    description: Text("切换左侧范围或点击刷新。")
                )
            }
        }
        .navigationTitle("Codex TaskGuard")
    }
}

private struct GroupRowView: View {
    let group: ServiceGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .foregroundStyle(iconColor)
                    .frame(width: 18)

                Text(group.title)
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                RiskBadge(risk: group.risk)
            }

            HStack(spacing: 8) {
                Text(group.ownership.displayName)
                Text("\(group.processCount) 进程")
                if !group.listeningPorts.isEmpty {
                    Text(":\(group.listeningPorts.map(String.init).joined(separator: ", :"))")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let cwd = group.cwd {
                Text(cwd)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else if let process = group.primaryProcess {
                Text(process.commandSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }

    private var iconName: String {
        switch group.ownership {
        case .codexThread: return "bubble.left.and.text.bubble.right"
        case .codexWorkspace: return "folder"
        case .codexInternal: return "gearshape.2"
        case .developmentService: return "terminal"
        case .listeningPort: return "network"
        case .unownedDevelopment: return "questionmark.app"
        case .protected: return "lock.shield"
        }
    }

    private var iconColor: Color {
        switch group.risk {
        case .suggestedCleanup: return .orange
        case .needsReview: return .blue
        case .protected: return .secondary
        }
    }
}

struct RiskBadge: View {
    let risk: ServiceRisk

    var body: some View {
        Text(risk.displayName)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(background)
            .foregroundStyle(foreground)
            .clipShape(Capsule())
    }

    private var background: Color {
        switch risk {
        case .suggestedCleanup: return .orange.opacity(0.16)
        case .needsReview: return .blue.opacity(0.14)
        case .protected: return .secondary.opacity(0.12)
        }
    }

    private var foreground: Color {
        switch risk {
        case .suggestedCleanup: return .orange
        case .needsReview: return .blue
        case .protected: return .secondary
        }
    }
}
