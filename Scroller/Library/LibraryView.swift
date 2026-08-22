import SwiftUI

/// Flow and Line are real tabs rather than a hand-rolled selector, so the
/// selection behaviour, the glass, and the animation are the system's own.
struct LibraryView: View {
    @Environment(PrompterSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        TabView(selection: $settings.mode) {
            // Text-only labels: this is an internal tool for people who know
            // the difference, and an icon for "Flow" would be a guess.
            Tab(value: PrompterMode.flow) {
                ScriptListView(mode: .flow)
            } label: {
                Text(PrompterMode.flow.title)
            }

            Tab(value: PrompterMode.line) {
                ScriptListView(mode: .line)
            } label: {
                Text(PrompterMode.line.title)
            }
        }
        .tint(.scrollerAccent)
    }
}

private struct ScriptListView: View {
    let mode: PrompterMode

    @Environment(ScriptLibrary.self) private var library
    @Environment(PrompterSettings.self) private var settings
    @Environment(\.scenePhase) private var scenePhase

    @State private var openedScript: Script?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    PasteButton(payloadType: String.self) { strings in
                        guard let text = strings.first,
                              let script = ScriptImport.makeScript(from: text) else { return }
                        library.add(script)
                        openedScript = script
                    }
                    .buttonBorderShape(.capsule)
                    .labelStyle(.titleAndIcon)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }

                Section {
                    ForEach(library.scripts) { script in
                        Button { openedScript = script } label: { row(script) }
                            .buttonStyle(.plain)
                    }
                    .onDelete { library.delete(at: $0) }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Scripts")
        }
        .onChange(of: scenePhase) { _, phase in
            // The share extension may have added a script while we were away.
            if phase == .active { library.reload() }
        }
        .fullScreenCover(item: $openedScript) { script in
            switch mode {
            case .flow: PrompterView(script: script)
            case .line: LineView(script: script)
            }
        }
    }

    private func row(_ script: Script) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(script.title)
                .font(.headline)
                .lineLimit(1)
            Text("\(script.wordCount) words · \(durationText(for: script))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func durationText(for script: Script) -> String {
        ReadingTime.spelled(words: script.wordCount, wordsPerMinute: settings.wordsPerMinute)
    }
}
