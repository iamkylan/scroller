import SwiftUI
import UIKit

final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        Task { @MainActor in
            let items = (self.extensionContext?.inputItems as? [NSExtensionItem]) ?? []
            let text = await SharedTextExtractor.text(from: items)
            self.install(text: text)
        }
    }

    private func install(text: String?) {
        let root = ShareRootView(
            text: text,
            isStorageAvailable: ScriptStore.isSharedContainerAvailable,
            onCancel: { [weak self] in self?.cancel() },
            onDone: { [weak self] in self?.complete() }
        )

        let host = UIHostingController(rootView: root)
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        host.didMove(toParent: self)
    }

    private func complete() {
        extensionContext?.completeRequest(returningItems: nil)
    }

    private func cancel() {
        extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
    }
}
