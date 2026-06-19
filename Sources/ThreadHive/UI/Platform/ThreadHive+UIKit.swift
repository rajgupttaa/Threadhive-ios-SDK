#if canImport(UIKit) && canImport(SwiftUI)
import UIKit
import SwiftUI

public extension ThreadHive {
    /// A ready-to-present chat view controller (a `UIHostingController` wrapping
    /// the SwiftUI chat). Nil until `configure(...)`. The header's close button
    /// dismisses it.
    @MainActor
    static func chatViewController() -> UIViewController? {
        guard let model = makeChatViewModel() else { return nil }
        var dismiss: (() -> Void)?
        let hosting = UIHostingController(rootView: ThreadHiveChatView(model: model, onClose: { dismiss?() }))
        dismiss = { [weak hosting] in hosting?.dismiss(animated: true) }
        return hosting
    }

    /// Present the chat modally from a host view controller.
    @MainActor
    static func presentChat(from presenter: UIViewController, animated: Bool = true) {
        guard let controller = chatViewController() else { return }
        controller.modalPresentationStyle = .automatic
        presenter.present(controller, animated: animated)
    }
}
#endif
