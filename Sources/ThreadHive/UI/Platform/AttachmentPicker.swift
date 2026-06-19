#if os(iOS)
import SwiftUI
import UniformTypeIdentifiers

/// File/photo picker for composer attachments. Returns the raw bytes + a name +
/// a MIME type, ready to hand to `ChatViewModel.upload`.
struct AttachmentPicker: UIViewControllerRepresentable {
    let onPick: (Data, String, String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // Matches the backend allow-list: png/jpg/jpeg/gif/webp/pdf.
        var types: [UTType] = [.png, .jpeg, .gif, .pdf, .image]
        if let webp = UTType("org.webmproject.webp") { types.append(webp) }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (Data, String, String) -> Void
        init(onPick: @escaping (Data, String, String) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { return }
            onPick(data, url.lastPathComponent, WidgetAPIClient.mimeType(forExtension: url.pathExtension))
        }
    }
}
#endif
