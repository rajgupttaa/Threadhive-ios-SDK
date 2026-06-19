#if canImport(SwiftUI)
import SwiftUI

/// Circular avatar — remote image when available, else initials on the brand color.
struct AvatarView: View {
    let name: String
    let avatarURL: String?
    let theme: ThreadHiveTheme
    var size: CGFloat = 28

    private var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map(String.init).joined()
        return letters.isEmpty ? "•" : letters.uppercased()
    }

    var body: some View {
        Group {
            if let urlString = avatarURL, let url = URL(string: urlString) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    initialsCircle
                }
            } else {
                initialsCircle
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private var initialsCircle: some View {
        ZStack {
            theme.brand
            Text(initials)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundColor(.white)
        }
    }
}

/// Animated "agent is typing" dots.
struct TypingIndicatorView: View {
    let theme: ThreadHiveTheme
    @State private var phase = 0.0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 7, height: 7)
                    .opacity(phase == Double(index) ? 1 : 0.3)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(theme.botBubble)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onAppear {
            withAnimation(.easeInOut(duration: 0.6).repeatForever()) { phase = 2 }
        }
        .accessibilityLabel("Typing")
    }
}

/// Retrieval citation chips under a bot bubble.
struct CitationChipsView: View {
    let citations: [AskSource]
    let theme: ThreadHiveTheme
    let onTap: (AskSource) -> Void

    var body: some View {
        if !citations.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(citations) { source in
                        Button {
                            onTap(source)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "doc.text")
                                    .font(.system(size: 9))
                                Text(source.sourceName)
                                    .font(.system(size: 11, weight: .medium))
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(theme.brand.opacity(0.1))
                            .foregroundColor(theme.brand)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(source.chunkURL == nil)
                    }
                }
            }
        }
    }
}

extension AskSource: Identifiable {
    public var id: String { sourceID + (chunkURL ?? "") }
}

/// Product card with image, price, and View / Add actions.
struct ProductCardView: View {
    let product: Product
    let theme: ThreadHiveTheme
    let onOpen: (Product) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let imageURLString = product.imageURL, let url = URL(string: imageURLString) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    theme.botBubble
                }
                .frame(height: 120)
                .frame(maxWidth: .infinity)
                .clipped()
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(product.title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(2)
                if let price = product.price {
                    Text(priceLabel(price, currency: product.currency))
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                if !product.inStock {
                    Text("Out of stock")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.orange)
                }
                HStack(spacing: 8) {
                    Button { onOpen(product) } label: {
                        Text("View").font(.system(size: 13, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.divider))
                    }
                    .buttonStyle(.plain)
                    Button { onOpen(product) } label: {
                        Text("Add").font(.system(size: 13, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(theme.brand)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .disabled(product.url == nil)
                    .opacity(product.url == nil ? 0.5 : 1)
                }
                .padding(.top, 2)
            }
            .padding(10)
        }
        .background(theme.botBubble)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .frame(width: 200)
    }

    private func priceLabel(_ price: String, currency: String?) -> String {
        guard let currency, !currency.isEmpty else { return price }
        let symbols = ["USD": "$", "EUR": "€", "GBP": "£"]
        if let symbol = symbols[currency.uppercased()] { return "\(symbol)\(price)" }
        return "\(price) \(currency)"
    }
}

/// Confirm / Cancel prompt for a bot-prepared action.
struct PendingActionView: View {
    let action: PendingAction
    let theme: ThreadHiveTheme
    let onConfirm: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.shield")
                    .foregroundColor(theme.brand)
                Text(action.label)
                    .font(.system(size: 13, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Button { onConfirm(false) } label: {
                    Text("Cancel").font(.system(size: 13, weight: .medium))
                        .frame(maxWidth: .infinity).padding(.vertical, 7)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.divider))
                }
                .buttonStyle(.plain)
                Button { onConfirm(true) } label: {
                    Text("Confirm").font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity).padding(.vertical, 7)
                        .background(theme.brand).foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(theme.brand.opacity(0.06))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.brand.opacity(0.25)))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// An attached image (thumbnail) or file chip inside a message bubble.
struct AttachmentChipView: View {
    let attachment: MessageAttachment
    let url: URL?
    let theme: ThreadHiveTheme

    var body: some View {
        if attachment.isImage, let url {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                theme.botBubble
            }
            .frame(width: 140, height: 140)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            HStack(spacing: 6) {
                Image(systemName: "paperclip")
                Text(attachment.name).font(.system(size: 12)).lineLimit(1)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(theme.botBubble)
            .clipShape(Capsule())
        }
    }
}
#endif
