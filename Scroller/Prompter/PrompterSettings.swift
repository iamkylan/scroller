import Foundation

@MainActor
@Observable
final class PrompterSettings {
    static let fontSizeRange: ClosedRange<Double> = 22...170
    static let wordsPerMinuteRange: ClosedRange<Double> = 70...260

    var fontSize: Double { didSet { store(fontSize, "fontSize") } }
    var wordsPerMinute: Double { didSet { store(wordsPerMinute, "wordsPerMinute") } }
    var isMirrored: Bool { didSet { store(isMirrored, "isMirrored") } }
    var isVoiceTracking: Bool { didSet { store(isVoiceTracking, "isVoiceTracking") } }
    /// Where the reading line sits, as a fraction of screen height.
    var eyeLineFraction: Double { didSet { store(eyeLineFraction, "eyeLineFraction") } }

    private let defaults = UserDefaults.standard

    init() {
        defaults.register(defaults: [
            "fontSize": 46.0,
            "wordsPerMinute": 140.0,
            "isMirrored": false,
            "isVoiceTracking": true,
            "eyeLineFraction": 0.36,
        ])
        fontSize = defaults.double(forKey: "fontSize")
        wordsPerMinute = defaults.double(forKey: "wordsPerMinute")
        isMirrored = defaults.bool(forKey: "isMirrored")
        isVoiceTracking = defaults.bool(forKey: "isVoiceTracking")
        eyeLineFraction = defaults.double(forKey: "eyeLineFraction")
    }

    private func store(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
    }
}
