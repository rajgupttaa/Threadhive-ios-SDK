#if canImport(SwiftUI)
import SwiftUI

/// Renders one chat row, dispatching on author kind.
struct MessageRowView: View {
    let message: ChatMessage
    let theme: ThreadHiveTheme
    let attachmentURL: (MessageAttachment) -> URL?
    let onOpenCitation: (AskSource) -> Void
    let onOpenProduct: (Product) -> Void
    let onConfirm: (PendingAction, Bool) -> Void

    var body: some View {
        switch message.author {
        case .system: systemRow
        case .visitor: visitorRow
        case .bot, .agent: assistantRow
        }
    }

    // MARK: System

    private var systemRow: some View {
        Text(message.text)
            .font(.system(size: 12))
            .foregroundColor(theme.systemText)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(theme.botBubble)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
    }

    // MARK: Visitor

    private var visitorRow: some View {
        HStack {
            Spacer(minLength: 40)
            VStack(alignment: .trailing, spacing: 4) {
                ForEach(message.attachments) { attachment in
                    AttachmentChipView(attachment: attachment, url: attachmentURL(attachment), theme: theme)
                }
                if !message.text.isEmpty {
                    Text(message.text)
                        .font(.system(size: 15))
                        .foregroundColor(theme.userBubbleText)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(theme.userBubble)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                if message.sendState == .sending {
                    Text("Sending…").font(.system(size: 10)).foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: Bot / Agent

    private var assistantRow: some View {
        HStack(alignment: .top, spacing: 8) {
            AvatarView(name: message.authorName.isEmpty ? "ThreadHive" : message.authorName,
                       avatarURL: message.avatarURL, theme: theme)
            VStack(alignment: .leading, spacing: 6) {
                if message.author == .agent, !message.authorName.isEmpty {
                    Text(message.authorName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                ForEach(message.attachments) { attachment in
                    AttachmentChipView(attachment: attachment, url: attachmentURL(attachment), theme: theme)
                }
                if !message.text.isEmpty {
                    Text(message.text)
                        .font(.system(size: 15))
                        .foregroundColor(theme.botBubbleText)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(theme.botBubble)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .textSelection(.enabled)
                }
                CitationChipsView(citations: message.citations, theme: theme, onTap: onOpenCitation)
                if !message.products.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(message.products) { product in
                                ProductCardView(product: product, theme: theme, onOpen: onOpenProduct)
                            }
                        }
                    }
                }
                ForEach(message.pendingActions) { action in
                    PendingActionView(action: action, theme: theme) { accept in
                        onConfirm(action, accept)
                    }
                }
            }
            Spacer(minLength: 40)
        }
    }
}
#endif
