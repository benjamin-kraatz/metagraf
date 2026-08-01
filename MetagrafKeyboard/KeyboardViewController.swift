import MetagrafCore
import OSLog
import SwiftUI
import UIKit

/// The Metagraf keyboard.
///
/// Deliberately not a full keyboard: it does one thing the system keyboard
/// cannot, which is dictate with Metagraf's model, vocabulary, and formatting,
/// and it inserts straight into whatever field is focused. The globe key hands
/// back to the user's usual keyboard for everything else.
final class KeyboardViewController: UIInputViewController {
    private let logger = Logger(subsystem: Metagraf.bundleIdentifier, category: "Keyboard")
    private var model: KeyboardModel?

    override func viewDidLoad() {
        super.viewDidLoad()

        let model = KeyboardModel(
            hasFullAccess: hasFullAccess,
            insert: { [weak self] text in
                self?.textDocumentProxy.insertText(text)
            },
            deleteBackward: { [weak self] in
                self?.textDocumentProxy.deleteBackward()
            },
            advanceToNextKeyboard: { [weak self] in
                self?.advanceToNextInputMode()
            }
        )
        self.model = model

        let host = UIHostingController(rootView: KeyboardView(model: model))
        host.view.backgroundColor = .clear

        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            // Keyboards have no intrinsic height; without this the input view
            // collapses to nothing.
            view.heightAnchor.constraint(equalToConstant: 268),
        ])
        host.didMove(toParent: self)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // The extension can be torn down at any moment; never leave the
        // microphone running behind a dismissed keyboard.
        model?.stopImmediately()
    }
}
