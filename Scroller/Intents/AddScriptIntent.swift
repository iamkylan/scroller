import AppIntents

/// Lets Shortcuts (and therefore automations) drop text straight into the
/// library without opening the app.
struct AddScriptIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Script to Scroller"
    static let description = IntentDescription("Saves text as a new script you can read in the prompter.")
    static let openAppWhenRun = false

    @Parameter(title: "Text", inputOptions: String.IntentInputOptions(multiline: true))
    var text: String

    @Parameter(title: "Title", description: "Leave empty to use the first line of the text.")
    var scriptTitle: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$text) to Scroller as \(\.$scriptTitle)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        guard let script = ScriptImport.makeScript(from: text, title: scriptTitle) else {
            throw AddScriptError.emptyText
        }
        ScriptStore.add(script)
        return .result(value: script.title)
    }
}

enum AddScriptError: Error, CustomLocalizedStringResourceConvertible {
    case emptyText

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .emptyText: "There was no text to save."
        }
    }
}

struct ScrollerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddScriptIntent(),
            phrases: ["Add a script to \(.applicationName)"],
            shortTitle: "Add Script",
            systemImageName: "text.line.first.and.arrowtriangle.forward"
        )
    }
}
