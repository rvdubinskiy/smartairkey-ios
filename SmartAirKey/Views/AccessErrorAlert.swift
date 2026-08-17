import SwiftUI
import UIKit

/// Presents an `AccessError` as a native alert where the **primary call to
/// action** (e.g. "Open Settings") is the emphasised/focused button, and the
/// dismiss button ("Got It") is the plain one.
///
/// SwiftUI's own `Alert` always emphasises the `.cancel` button, which put the
/// accent on "Close" instead of the action the user actually needs. `UIAlert‑
/// Controller.preferredAction` is the only way to move that emphasis onto the
/// call to action, so we bridge to UIKit here.
private struct AccessErrorAlertPresenter: UIViewControllerRepresentable {

    @Binding var error: AccessError?
    let onPrimary: (AccessError, ErrorAction) -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {
        // Nothing to show, or an alert is already up — leave it be.
        guard let error else { return }
        guard controller.presentedViewController == nil else { return }

        let alert = UIAlertController(title: error.title,
                                      message: error.message,
                                      preferredStyle: .alert)

        let action = error.primaryAction
        let primary = UIAlertAction(title: action.title, style: .default) { _ in
            self.error = nil
            // Pass the resolved error so the handler can route to the right
            // Settings screen (the binding is already cleared above).
            onPrimary(error, action)
        }
        // The dismiss button is deliberately *not* a `.cancel` action: UIKit
        // always renders `.cancel` bold, which stole the emphasis from the real
        // call to action. `.destructive` renders it red and unemphasised so the
        // focus stays on "Open Settings" — the user should go to Settings, not
        // just close the dialog.
        let dismiss = UIAlertAction(title: L10n.string("common.close"), style: .destructive) { _ in
            self.error = nil
        }
        alert.addAction(primary)
        alert.addAction(dismiss)
        // Emphasise the call to action ("Open Settings" / "Try Again" / "Contact
        // Support") — it becomes the bold, default-tinted button.
        alert.preferredAction = primary

        DispatchQueue.main.async {
            guard controller.presentedViewController == nil else { return }
            controller.present(alert, animated: true)
        }
    }
}

extension View {

    /// Shows an emphasised-action alert for the bound `AccessError` (UI req. 4).
    /// The primary action button is focused; the dismiss button is secondary.
    /// The `onPrimary` handler receives the resolved error and its action.
    func accessErrorAlert(_ error: Binding<AccessError?>,
                          onPrimary: @escaping (AccessError, ErrorAction) -> Void) -> some View {
        background(AccessErrorAlertPresenter(error: error, onPrimary: onPrimary))
    }
}
