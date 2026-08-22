import SwiftUI

struct LibraryView: View {
    @Environment(ScriptLibrary.self) private var library
    @Environment(PrompterSettings.self) private var settings

    @State private var openedScript: Script?

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var settings = settings

        return NavigationStack {
            List {
                Section {
                    Picker("Mode", selection: $settings.mode) {
                        ForEach(PrompterMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                    Text(settings.mode.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

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
            // Which way you're shooting is decided before you start, so the
            // choice lives here rather than adding chrome to the prompter.
            switch settings.mode {
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
