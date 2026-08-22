import Foundation

enum PrompterMode: String, CaseIterable, Identifiable, Sendable {
    /// Continuous scrolling for a live, straight-through delivery.
    case flow
    /// One beat at a time, for reading a line then performing it to camera.
    case line

    var id: String { rawValue }

    var title: String {
        switch self {
        case .flow: "Flow"
        case .line: "Line"
        }
    }
}

@MainActor
@Observable
final class PrompterSettings {
    static let fontSizeRange: ClosedRange<Double> = 22...170
    static let wordsPerMinuteRange: ClosedRange<Double> = 70...260

    var mode: PrompterMode {
        didSet { store(mode.rawValue, "mode") }
    }

    var fontSize: Double { didSet { store(fontSize, "fontSize") } }
    /// Line mode shows one sentence on a card, which wants to be far larger
    /// than scrolling body text, so the two sizes are remembered separately.
    var lineFontSize: Double { didSet { store(lineFontSize, "lineFontSize") } }
    var wordsPerMinute: Double { didSet { store(wordsPerMinute, "wordsPerMinute") } }
    var isMirrored: Bool { didSet { store(isMirrored, "isMirrored") } }
    var isVoiceTracking: Bool { didSet { store(isVoiceTracking, "isVoiceTracking") } }
    /// Where the reading line sits, as a fraction of screen height.
    var eyeLineFraction: Double { didSet { store(eyeLineFraction, "eyeLineFraction") } }

    private let defaults = UserDefaults.standard

    init() {
        defaults.register(defaults: [
            "mode": PrompterMode.flow.rawValue,
            "fontSize": 46.0,
            "lineFontSize": 62.0,
            "wordsPerMinute": 140.0,
            "isMirrored": false,
            "isVoiceTracking": true,
            "eyeLineFraction": 0.36,
        ])
        mode = PrompterMode(rawValue: defaults.string(forKey: "mode") ?? "") ?? .flow
        fontSize = defaults.double(forKey: "fontSize")
        lineFontSize = defaults.double(forKey: "lineFontSize")
        wordsPerMinute = defaults.double(forKey: "wordsPerMinute")
        isMirrored = defaults.bool(forKey: "isMirrored")
        isVoiceTracking = defaults.bool(forKey: "isVoiceTracking")
        eyeLineFraction = defaults.double(forKey: "eyeLineFraction")
    }

    private func store(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
    }
}
