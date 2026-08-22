import Foundation

@MainActor
@Observable
final class PrompterModel {
    let proxy = PrompterTextProxy()

    private(set) var isRunning = false
    private(set) var countdown: Int?

    var wordsPerMinute: Double = 140
    var readingLineY: Double = 0

    private let engine = ScrollEngine()
    private let wordCount: Int
    private var countdownTask: Task<Void, Never>?

    init(wordCount: Int) {
        self.wordCount = max(1, wordCount)
        engine.onTick = { [weak self] elapsed in
            self?.tick(elapsed)
        }
    }

    var isActive: Bool { isRunning || countdown != nil }

    func toggle() {
        if isActive { stop() } else { start() }
    }

    func start() {
        guard !isActive else { return }
        if proxy.hasReachedEnd { proxy.offsetY = 0 }

        countdownTask = Task { [weak self] in
            for value in stride(from: 3, through: 1, by: -1) {
                self?.countdown = value
                do {
                    try await Task.sleep(for: .milliseconds(650))
                } catch {
                    self?.countdown = nil
                    return
                }
            }
            self?.countdown = nil
            self?.isRunning = true
            self?.engine.start()
        }
    }

    func stop() {
        countdownTask?.cancel()
        countdownTask = nil
        countdown = nil
        isRunning = false
        engine.stop()
    }

    func restart() {
        stop()
        proxy.offsetY = 0
    }

    /// Derived from the live layout, so a pinch changes how many points scroll
    /// past per second without changing the pace you actually have to speak at.
    private var pointsPerSecond: Double {
        let pointsPerWord = proxy.textHeight / Double(wordCount)
        return wordsPerMinute / 60.0 * pointsPerWord
    }

    private func tick(_ elapsed: Double) {
        proxy.offsetY += pointsPerSecond * elapsed
        if proxy.hasReachedEnd { stop() }
    }
}
