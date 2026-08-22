import SwiftUI

struct LibraryView: View {
    @Environment(ScriptLibrary.self) private var library
    @Environment(PrompterSettings.self) private var settings

    @State private var openedScript: Script?
    @Namespace private var modeSelection

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var settings = settings

        return NavigationStack {
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
            .safeAreaInset(edge: .bottom) {
                modeBar(selection: $settings.mode)
            }
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

    /// How you're shooting is a session-level choice, so it sits apart from
    /// the list rather than competing with it for the top of the screen.
    private func modeBar(selection: Binding<PrompterMode>) -> some View {
        HStack(spacing: 4) {
            ForEach(PrompterMode.allCases) { mode in
                Button {
                    selection.wrappedValue = mode
                } label: {
                    Text(mode.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(selection.wrappedValue == mode ? .black : .primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background {
                            if selection.wrappedValue == mode {
                                Capsule()
                                    .fill(Color.scrollerAccent)
                                    .matchedGeometryEffect(id: "mode", in: modeSelection)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .frame(width: 236)
        .background(.regularMaterial, in: .capsule)
        .shadow(color: .black.opacity(0.35), radius: 18, y: 6)
        .padding(.bottom, 6)
        .animation(.snappy(duration: 0.28), value: selection.wrappedValue)
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
