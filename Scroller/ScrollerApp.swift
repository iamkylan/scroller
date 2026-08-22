import SwiftUI

@main
struct ScrollerApp: App {
    @State private var library = ScriptLibrary()
    @State private var settings = PrompterSettings()

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environment(library)
                .environment(settings)
                .preferredColorScheme(.dark)
                .tint(.scrollerAccent)
        }
    }
}
