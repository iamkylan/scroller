import Foundation

/// Records how far voice startup got, so a crash on a device we can't attach a
/// debugger to still says where it happened. Each stage is written before it
/// runs; if the app dies mid-stage the marker survives into the next launch.
enum VoiceDiagnostics {
    enum Step: String {
        case permissions = "requesting permissions"
        case locale = "choosing a language"
        case model = "loading the language model"
        case analyzer = "starting the analyzer"
        case audioSession = "configuring the audio session"
        case audioEngine = "opening the microphone"
        case tap = "attaching the audio tap"
        case engineStart = "starting the audio engine"
    }

    private static let stepKey = "voiceStartupStep"
    private static let inProgressKey = "voiceStartupInProgress"

    /// The stage the previous run was in when it stopped, if it never finished.
    /// Read once, before anything overwrites it.
    static let unfinishedStepAtLaunch: String? = {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: inProgressKey) else { return nil }
        return defaults.string(forKey: stepKey)
    }()

    static func begin(_ step: Step) {
        // Forces the launch snapshot to be taken before the first overwrite.
        _ = unfinishedStepAtLaunch
        let defaults = UserDefaults.standard
        defaults.set(step.rawValue, forKey: stepKey)
        defaults.set(true, forKey: inProgressKey)
    }

    /// Reached the end, or failed in a way we caught and reported. Either way
    /// the app is still alive, so there's nothing to report next launch.
    static func finish() {
        _ = unfinishedStepAtLaunch
        UserDefaults.standard.set(false, forKey: inProgressKey)
    }
}
