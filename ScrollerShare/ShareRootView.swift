import SwiftUI

struct ShareRootView: View {
    let text: String?
    let isStorageAvailable: Bool
    let onCancel: () -> Void
    let onDone: () -> Void

    @State private var title = ""
    @State private var didSave = false

    private var script: Script? {
        text.flatMap { ScriptImport.makeScript(from: $0) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if didSave {
                    message(symbol: "checkmark.circle.fill", tint: .green, title: "Saved to Scroller")
                } else if !isStorageAvailable {
                    message(
                        symbol: "exclamationmark.triangle.fill",
                        tint: .orange,
                        title: "Can't reach Scroller's storage",
                        detail: "The App Group entitlement is missing, so this script couldn't be handed to the app."
                    )
                } else if let script {
                    editor(for: script)
                } else {
                    message(
                        symbol: "text.badge.xmark",
                        tint: .secondary,
                        title: "No text to import",
                        detail: "Scroller couldn't find any readable text in what you shared."
                    )
                }
            }
            .navigationTitle("Add to Scroller")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(script == nil || !isStorageAvailable)
                }
            }
        }
    }

    private func editor(for script: Script) -> some View {
        Form {
            Section("Title") {
                TextField("Title", text: $title, prompt: Text(script.title))
            }
            Section {
                Text(script.body)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } header: {
                Text("\(script.wordCount) words · \(ReadingTime.spelled(words: script.wordCount, wordsPerMinute: 140)) at 140 wpm")
            }
        }
    }

    private func message(
        symbol: String,
        tint: Color,
        title: String,
        detail: String? = nil
    ) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
                .foregroundStyle(tint)
        } description: {
            if let detail { Text(detail) }
        }
    }

    private func save() {
        guard let text, let script = ScriptImport.makeScript(from: text, title: title) else { return }
        ScriptStore.add(script)
        didSave = true
        // Long enough to register as confirmation, short enough not to be a wait.
        Task {
            try? await Task.sleep(for: .milliseconds(650))
            onDone()
        }
    }
}
