import MetagrafCore
import OSLog
import SwiftUI
import UIKit

/// The Metagraf keyboard.
///
/// Deliberately not a full keyboard: it puts what you dictated in the app into
/// whatever field is focused, without leaving that field. The globe key hands
/// back to the user's usual keyboard for everything else.
///
/// It does not dictate. iOS refuses microphone access to app extensions, so
/// capture happens in the app and only insertion happens here.
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

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // The app may have dictated something since this keyboard was last
        // shown, so the list is re-read every time rather than once at load.
        model?.refresh()
    }
}
