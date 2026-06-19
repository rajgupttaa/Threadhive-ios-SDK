#if canImport(SwiftUI)
import SwiftUI

/// The "Messages" tab — the visitor's past conversations. Tap to reopen, or start
/// a new one. Presented as a sheet from the chat header.
struct MessagesListView: View {
    @ObservedObject var model: ChatViewModel
    let theme: ThreadHiveTheme
    let onSelect: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Your conversations").font(.system(size: 17, weight: .semibold))
                Spacer()
                Button {
                    model.startNewConversation()
                    onSelect()
                } label: {
                    Label("New", systemImage: "square.and.pencil").font(.system(size: 14, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundColor(theme.brand)
            }
            .padding(16)

            if model.pastConversations.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "bubble.left.and.bubble.right").font(.system(size: 32)).foregroundColor(.secondary)
                    Text("No conversations yet").foregroundColor(.secondary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.pastConversations) { conversation in
                            Button {
                                model.reopen(conversation)
                                onSelect()
                            } label: {
                                row(conversation)
                            }
                            .buttonStyle(.plain)
                            Divider().padding(.leading, 16)
                        }
                    }
                }
            }
        }
        .task { await model.loadConversations() }
    }

    private func row(_ conversation: ConversationSummary) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(theme.brand.opacity(0.12)).frame(width: 40, height: 40)
                Image(systemName: conversation.aiHandled ? "sparkles" : "person.fill")
                    .foregroundColor(theme.brand)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(conversation.subject).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                Text(conversation.lastMessagePreview).font(.system(size: 13)).foregroundColor(.secondary).lineLimit(1)
            }
            Spacer()
            if conversation.status == .closed {
                Text("Closed").font(.system(size: 11)).foregroundColor(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(theme.botBubble).clipShape(Capsule())
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}
#endif
