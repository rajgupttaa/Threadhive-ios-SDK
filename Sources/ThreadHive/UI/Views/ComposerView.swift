#if canImport(SwiftUI)
import SwiftUI

/// Bottom composer: optional banner, pending-upload tray, attach button, text
/// field, and send. Emits typing pings as the visitor types.
struct ComposerView: View {
    @ObservedObject var model: ChatViewModel
    let theme: ThreadHiveTheme
    var onPickAttachment: (() -> Void)?

    private var canSend: Bool {
        !model.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !model.pendingUploads.isEmpty
    }

    var body: some View {
        VStack(spacing: 8) {
            if let banner = model.banner {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill").foregroundColor(.orange)
                    Text(banner).font(.system(size: 12)).foregroundColor(.primary)
                    Spacer()
                    Button { model.dismissBanner() } label: { Image(systemName: "xmark").font(.system(size: 10)) }
                        .buttonStyle(.plain).foregroundColor(.secondary)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color.orange.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            if !model.pendingUploads.isEmpty || model.isUploading {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(model.pendingUploads) { upload in
                            HStack(spacing: 4) {
                                Image(systemName: upload.isImage ? "photo" : "paperclip").font(.system(size: 11))
                                Text(upload.name).font(.system(size: 11)).lineLimit(1)
                                Button { model.removeUpload(upload) } label: {
                                    Image(systemName: "xmark.circle.fill").font(.system(size: 12)).foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .background(theme.botBubble).clipShape(Capsule())
                        }
                        if model.isUploading { ProgressView().scaleEffect(0.7) }
                    }
                }
            }

            HStack(spacing: 8) {
                if let onPickAttachment {
                    Button(action: onPickAttachment) {
                        Image(systemName: "paperclip")
                            .font(.system(size: 18))
                            .foregroundColor(model.canAttach ? theme.brand : .secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(!model.canAttach)
                    .accessibilityLabel("Attach a file")
                }

                TextField("Type a message…", text: $model.inputText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(theme.botBubble)
                    .clipShape(Capsule())
                    .onChange(of: model.inputText) { _ in model.userIsTyping() }
                    .onSubmit { model.send() }
                    .submitLabel(.send)

                Button { model.send() } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                        .foregroundColor(canSend ? theme.brand : .secondary.opacity(0.5))
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .accessibilityLabel("Send")
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(theme.chatBackground)
        .overlay(Rectangle().fill(theme.divider).frame(height: 0.5), alignment: .top)
    }
}
#endif
