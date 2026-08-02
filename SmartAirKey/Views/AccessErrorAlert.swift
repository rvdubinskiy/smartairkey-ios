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
    let onPrimary: (ErrorAction) -> Void

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
            onPrimary(action)
        }
        let dismiss = UIAlertAction(title: L10n.string("common.ok"), style: .cancel) { _ in
            self.error = nil
        }
        alert.addAction(primary)
        alert.addAction(dismiss)
        // Focus the call to action ("Open Settings" / "Try Again" / "Contact
        // Support"), not the dismiss button.
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
    func accessErrorAlert(_ error: Binding<AccessError?>,
                          onPrimary: @escaping (ErrorAction) -> Void) -> some View {
        background(AccessErrorAlertPresenter(error: error, onPrimary: onPrimary))
    }
}
