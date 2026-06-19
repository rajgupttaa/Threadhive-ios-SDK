#if canImport(SwiftUI)
import SwiftUI

/// Brand-gradient header: who you're chatting with, online/away + reply time,
/// and a close affordance. Swaps to the assigned agent once a teammate joins.
struct ChatHeaderView: View {
    @ObservedObject var model: ChatViewModel
    let theme: ThreadHiveTheme
    var onClose: (() -> Void)?
    var onShowHistory: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            leading
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                HStack(spacing: 5) {
                    Circle()
                        .fill(model.isOnline ? Color.green : Color.white.opacity(0.5))
                        .frame(width: 7, height: 7)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(1)
                }
            }
            Spacer()
            if let onShowHistory {
                Button(action: onShowHistory) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Color.white.opacity(0.15))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Past conversations")
            }
            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Color.white.opacity(0.15))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close chat")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            LinearGradient(colors: [theme.brand, theme.accent], startPoint: .topLeading, endPoint: .bottomTrailing)
        )
    }

    @ViewBuilder
    private var leading: some View {
        if let agent = model.assignedAgent {
            AvatarView(name: agent.name, avatarURL: agent.avatarURL, theme: theme, size: 38)
                .overlay(Circle().stroke(Color.white.opacity(0.6), lineWidth: 1.5))
        } else if model.team.isEmpty {
            AvatarView(name: model.resolved.botName, avatarURL: nil, theme: theme, size: 38)
                .overlay(Circle().stroke(Color.white.opacity(0.6), lineWidth: 1.5))
        } else {
            TeamFacesView(team: model.team, overflow: model.teamOverflow, theme: theme)
        }
    }

    private var title: String {
        if let agent = model.assignedAgent { return agent.name }
        if !model.workspaceName.isEmpty { return model.workspaceName }
        return model.resolved.botName
    }

    private var subtitle: String {
        if model.agentTyping { return "Typing…" }
        if model.assignedAgent != nil { return "Active now" }
        if !model.isOnline { return "Away — we'll reply by email" }
        if let label = model.replyTimeLabel { return "Typically replies \(label)" }
        return model.aiAvailable ? "AI agent + human team" : "We're here to help"
    }
}

/// Overlapping team avatars with a "+N" overflow chip.
struct TeamFacesView: View {
    let team: [WidgetTeamMember]
    let overflow: Int
    let theme: ThreadHiveTheme

    var body: some View {
        HStack(spacing: -10) {
            ForEach(Array(team.prefix(3).enumerated()), id: \.offset) { _, member in
                AvatarView(name: member.name, avatarURL: member.avatarURL, theme: theme, size: 34)
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
            }
            if overflow > 0 {
                ZStack {
                    Circle().fill(Color.white.opacity(0.25))
                    Text("+\(overflow)").font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
                }
                .frame(width: 34, height: 34)
                .overlay(Circle().stroke(Color.white, lineWidth: 2))
            }
        }
    }
}
#endif
