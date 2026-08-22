import Foundation

/// Shared on-disk script list. Both the app and the share extension read and
/// write this, so every mutation goes through NSFileCoordinator rather than a
/// plain atomic write — otherwise a save from the extension can land on top of
/// a save from the app and one of them silently disappears.
enum ScriptStore {
    /// Read from the bundle rather than hardcoded, so the identifier lives in
    /// exactly one place — APP_GROUP_ID in project.yml, which also fills in the
    /// entitlements. App Group identifiers are globally unique across all Apple
    /// accounts, so this is a string that genuinely does get changed.
    static let appGroupID: String = {
        Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String
            ?? "group.com.kylan.scroller.shared"
    }()

    /// False when the App Group entitlement is missing or misspelled. The app
    /// falls back to its own container so it still works; the share extension
    /// surfaces it as an error, because writing somewhere the app can't read
    /// would look like the share silently did nothing.
    static var isSharedContainerAvailable: Bool { sharedContainerURL != nil }

    private static var sharedContainerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    private static var fileURL: URL {
        let directory = sharedContainerURL ?? URL.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "scripts.json")
    }

    static func load() -> [Script] {
        var result: [Script] = []
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: fileURL, options: [], error: &coordinationError) { url in
            guard let data = try? Data(contentsOf: url),
                  let decoded = try? JSONDecoder().decode([Script].self, from: data) else { return }
            result = decoded
        }
        return result
    }

    /// Read-modify-write under a single coordinated write, so concurrent saves
    /// from two processes serialize instead of overwriting each other.
    @discardableResult
    static func mutate(_ change: (inout [Script]) -> Void) -> [Script] {
        var result: [Script] = []
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: fileURL, options: [], error: &coordinationError) { url in
            var scripts: [Script] = {
                guard let data = try? Data(contentsOf: url) else { return [] }
                return (try? JSONDecoder().decode([Script].self, from: data)) ?? []
            }()
            change(&scripts)
            if let data = try? JSONEncoder().encode(scripts) {
                try? data.write(to: url, options: .atomic)
            }
            result = scripts
        }
        return result
    }

    static func add(_ script: Script) {
        mutate { $0.insert(script, at: 0) }
    }

    /// One-time move of the pre-App-Group file into the shared container.
    static func migrateLegacyStoreIfNeeded() {
        guard isSharedContainerAvailable else { return }
        let legacyURL = URL.applicationSupportDirectory.appending(path: "scripts.json")
        guard FileManager.default.fileExists(atPath: legacyURL.path),
              let data = try? Data(contentsOf: legacyURL),
              let legacy = try? JSONDecoder().decode([Script].self, from: data),
              !legacy.isEmpty
        else { return }

        mutate { scripts in
            let known = Set(scripts.map(\.id))
            scripts.append(contentsOf: legacy.filter { !known.contains($0.id) })
            scripts.sort { $0.updatedAt > $1.updatedAt }
        }
        try? FileManager.default.removeItem(at: legacyURL)
    }
}
