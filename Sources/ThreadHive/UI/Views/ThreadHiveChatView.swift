#if canImport(SwiftUI)
import SwiftUI

struct IdentifiedURL: Identifiable {
    let id = UUID()
    let url: URL
}

/// The full chat experience as a SwiftUI view: header, message list (with
/// auto-scroll + typing indicator), and composer. Embed it directly, or use
/// `ThreadHive.presentChat(from:)` / `chatViewController()` from UIKit.
public struct ThreadHiveChatView: View {
    @StateObject private var model: ChatViewModel
    private let onClose: (() -> Void)?
    @Environment(\.openURL) private var openURL
    @State private var browserURL: IdentifiedURL?
    @State private var showHistory = false
    #if os(iOS)
    @State private var showAttachmentPicker = false
    #endif

    /// Drive the view with a model you built (advanced / custom UIs).
    public init(model: ChatViewModel, onClose: (() -> Void)? = nil) {
        _model = StateObject(wrappedValue: model)
        self.onClose = onClose
    }

    /// Build from the configured `ThreadHive` session. Nil until `configure(...)`.
    @MainActor
    public init?(onClose: (() -> Void)? = nil) {
        guard let model = ThreadHive.makeChatViewModel() else { return nil }
        self.init(model: model, onClose: onClose)
    }

    private var theme: ThreadHiveTheme { ThreadHiveTheme(resolved: model.resolved) }

    public var body: some View {
        VStack(spacing: 0) {
            ChatHeaderView(model: model, theme: theme, onClose: onClose, onShowHistory: { showHistory = true })
            messageList
            ComposerView(model: model, theme: theme, onPickAttachment: attachmentHandler)
        }
        .background(theme.chatBackground.ignoresSafeArea())
        .preferredColorScheme(theme.preferredColorScheme)
        .sheet(isPresented: $showHistory) {
            MessagesListView(model: model, theme: theme, onSelect: { showHistory = false })
                .preferredColorScheme(theme.preferredColorScheme)
        }
        .onAppear {
            model.onOpenURL = { url in browserURL = IdentifiedURL(url: url) }
            model.onAppear()
        }
        .onDisappear { model.onDisappear() }
        .sheet(item: $browserURL) { item in
            #if os(iOS)
            SafariView(url: item.url).ignoresSafeArea()
            #else
            Color.clear.onAppear { openURL(item.url); browserURL = nil }
            #endif
        }
        #if os(iOS)
        .sheet(isPresented: $showAttachmentPicker) {
            AttachmentPicker { data, name, mime in
                model.upload(data: data, fileName: name, mimeType: mime)
            }
        }
        #endif
    }

    private var attachmentHandler: (() -> Void)? {
        #if os(iOS)
        return { showAttachmentPicker = true }
        #else
        return nil
        #endif
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(model.messages) { message in
                        MessageRowView(
                            message: message,
                            theme: theme,
                            attachmentURL: { model.attachmentURL($0) },
                            onOpenCitation: { model.openCitation($0) },
                            onOpenProduct: { model.open($0) },
                            onConfirm: { action, accept in model.confirm(action, accept: accept) }
                        )
                        .id(message.id)
                    }
                    if model.botThinking || model.agentTyping {
                        HStack { TypingIndicatorView(theme: theme); Spacer() }
                            .id("threadhive-typing")
                    }
                    Color.clear.frame(height: 1).id("threadhive-bottom")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 16)
            }
            .onChange(of: model.messages.count) { _ in scrollToBottom(proxy) }
            .onChange(of: model.botThinking) { _ in scrollToBottom(proxy) }
            .onChange(of: model.agentTyping) { _ in scrollToBottom(proxy) }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo("threadhive-bottom", anchor: .bottom)
        }
    }
}

/// A drop-in floating launcher (SwiftUI). Shows an unread badge and presents the
/// chat as a sheet. Hosts that prefer their own button can call
/// `ThreadHive.presentChat(from:)` instead.
public struct ThreadHiveLauncher: View {
    @State private var showChat = false
    @State private var unread = 0
    private let tint: Color?

    public init(tint: Color? = nil) { self.tint = tint }

    public var body: some View {
        Button { showChat = true } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 56, height: 56)
                    .background(tint ?? Color(threadHiveHex: ResolvedConfig.defaultBrandColor))
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                if unread > 0 {
                    Text("\(min(unread, 99))")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .padding(5)
                        .background(Color.red)
                        .clipShape(Circle())
                        .offset(x: 4, y: -4)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(unread > 0 ? "Open chat, \(unread) unread" : "Open chat")
        .onAppear { refreshUnread() }
        .sheet(isPresented: $showChat, onDismiss: refreshUnread) {
            if let chat = ThreadHiveChatView(onClose: { showChat = false }) {
                chat
            } else {
                Text("Chat is not configured.").padding()
            }
        }
    }

    private func refreshUnread() {
        ThreadHive.unreadCount { count in unread = count }
    }
}
#endif
