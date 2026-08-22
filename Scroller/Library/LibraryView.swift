import SwiftUI

/// Flow and Line are real tabs rather than a hand-rolled selector, so the
/// selection behaviour, the glass and the animation are the system's own.
struct LibraryView: View {
    @Environment(PrompterSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        TabView(selection: $settings.mode) {
            ForEach(PrompterMode.allCases) { mode in
                Tab(mode.title, systemImage: mode.symbol, value: mode) {
                    ScriptListView(mode: mode)
                }
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
                // Temporary while we chase the device crash: if the last voice
                // startup never finished, this says which stage it died in.
                if let step = VoiceDiagnostics.unfinishedStepAtLaunch {
                    Section {
                        Label(
                            "Voice tracking stopped while \(step)",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)
                    }
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
