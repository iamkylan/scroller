import SwiftUI

struct LibraryView: View {
    @Environment(PrompterSettings.self) private var settings
    @Namespace private var selectionGlass

    var body: some View {
        @Bindable var settings = settings

        ScriptListView(mode: settings.mode)
            .safeAreaInset(edge: .bottom) {
                ModeSwitch(selection: $settings.mode, namespace: selectionGlass)
            }
    }
}

/// Flow and Line are two modes of one screen, not two sections of an app, so
/// this is a mode switch rather than a tab bar. It borrows the tab bar's
/// mechanic — a glass container with a tinted glass selection that travels
/// between options — at a size you can read at arm's length on set.
private struct ModeSwitch: View {
    @Binding var selection: PrompterMode
    let namespace: Namespace.ID

    var body: some View {
        GlassEffectContainer(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(PrompterMode.allCases) { mode in
                    let isSelected = selection == mode
                    Button {
                        selection = mode
                    } label: {
                        Text(mode.title)
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(isSelected ? .black : .white.opacity(0.7))
                            .frame(width: 112, height: 46)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    // One piece of glass with one id, so it travels between the
                    // modes instead of one fading out as the other fades in.
                    .glassEffect(
                        isSelected ? .regular.tint(.scrollerAccent).interactive() : .identity,
                        in: .capsule
                    )
                    .glassEffectID(isSelected ? Optional("selection") : nil, in: namespace)
                }
            }
            .padding(5)
        }
        .glassEffect(.regular, in: .capsule)
        .padding(.bottom, 8)
        .animation(.snappy(duration: 0.32), value: selection)
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
