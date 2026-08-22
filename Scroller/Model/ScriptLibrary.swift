import Foundation

@MainActor
@Observable
final class ScriptLibrary {
    private(set) var scripts: [Script] = []

    init() {
        ScriptStore.migrateLegacyStoreIfNeeded()
        reload()
        if scripts.isEmpty {
            add(Script(title: Script.inferredTitle(from: Self.sampleBody), body: Self.sampleBody))
        }
    }

    /// Called when the app returns to the foreground: the share extension may
    /// have added a script to the shared container while we were backgrounded.
    func reload() {
        scripts = ScriptStore.load()
    }

    func add(_ script: Script) {
        scripts = ScriptStore.mutate { $0.insert(script, at: 0) }
    }

    func update(_ script: Script) {
        scripts = ScriptStore.mutate { scripts in
            guard let index = scripts.firstIndex(where: { $0.id == script.id }) else { return }
            var updated = script
            updated.updatedAt = .now
            scripts[index] = updated
        }
    }

    func delete(at offsets: IndexSet) {
        let doomed = Set(offsets.map { scripts[$0].id })
        scripts = ScriptStore.mutate { $0.removeAll { doomed.contains($0.id) } }
    }

    private static let sampleBody = """
    Welcome to Scroller

    This is a sample script so you can feel how the prompter moves before you \
    paste in anything real.

    Pinch anywhere on the text to make it bigger or smaller. The word you were \
    reading stays locked to the line marker while you do it, so you never lose \
    your place mid-take.

    Tap once to start scrolling, and tap again to stop. The speed is measured in \
    words per minute, which means changing the text size does not change how fast \
    you need to talk.

    Flip on mirror mode if you are shooting through a beam splitter, and drag the \
    line marker to wherever your eyeline naturally sits.

    That is everything for now. Voice tracking comes next, and when it lands the \
    text will follow your actual pace instead of a fixed one.
    """
}
