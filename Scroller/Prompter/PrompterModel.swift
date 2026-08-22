import Foundation

@MainActor
@Observable
final class PrompterModel {
    enum Mode: Equatable {
        case constant
        case voice
    }

    let proxy = PrompterTextProxy()
    let tracker = VoiceTracker()

    private(set) var isRunning = false
    private(set) var countdown: Int?

    var mode: Mode = .constant
    var wordsPerMinute: Double = 140
    var readingLineY: Double = 0 {
        didSet { refreshVoiceTarget() }
    }

    private let engine = ScrollEngine()
    private let script: Script
    private let wordCount: Int
    private var countdownTask: Task<Void, Never>?
    private var voiceTargetOffset: Double?

    /// How hard the scroll pulls toward the tracked word. Low enough that the
    /// text glides rather than snapping, which is what makes it watchable on
    /// camera; high enough to keep up with a fast reader.
    private let catchUpRate = 3.5

    init(script: Script) {
        self.script = script
        self.wordCount = max(1, script.wordCount)
        engine.onTick = { [weak self] elapsed in
            self?.tick(elapsed)
        }
        tracker.onPositionChanged = { [weak self] in
            self?.refreshVoiceTarget()
        }
    }

    var isActive: Bool { isRunning || countdown != nil }

    func toggle() {
        if isActive { stop() } else { start() }
    }

    func start() {
        guard !isActive else { return }
        if proxy.hasReachedEnd { proxy.offsetY = 0 }

        switch mode {
        case .voice:
            // No countdown: the prompter simply holds still until you speak,
            // which is a more natural cue than a number counting down.
            isRunning = true
            voiceTargetOffset = nil
            engine.start()
            Task { await tracker.start(script: script) }

        case .constant:
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
    }

    func stop() {
        countdownTask?.cancel()
        countdownTask = nil
        countdown = nil
        isRunning = false
        engine.stop()
        Task { await tracker.stop() }
    }

    func restart() {
        proxy.offsetY = 0
        voiceTargetOffset = nil
        if isActive {
            tracker.rewindToStart()
        } else {
            stop()
        }
    }

    /// Recomputed when the tracked word moves or the layout changes, rather
    /// than queried from TextKit on every frame.
    func refreshVoiceTarget() {
        guard mode == .voice,
              let index = tracker.characterIndex,
              let y = proxy.contentY(forCharacterIndex: index)
        else { return }
        voiceTargetOffset = y - readingLineY
    }

    /// Derived from the live layout, so a pinch changes how many points scroll
    /// past per second without changing the pace you actually have to speak at.
    private var pointsPerSecond: Double {
        let pointsPerWord = proxy.textHeight / Double(wordCount)
        return wordsPerMinute / 60 * pointsPerWord
    }

    private func tick(_ elapsed: Double) {
        switch mode {
        case .constant:
            proxy.offsetY += pointsPerSecond * elapsed
        case .voice:
            if isUsingFallbackPace {
                // Keep the take moving instead of freezing on a failure the
                // user can't act on right now.
                proxy.offsetY += pointsPerSecond * elapsed
            } else {
                steer(elapsed)
            }
        }
        if proxy.hasReachedEnd { stop() }
    }

    /// True when voice tracking has failed in a way that should silently hand
    /// over to constant-speed scrolling.
    var isUsingFallbackPace: Bool {
        guard case .failed(let failure) = tracker.status else { return false }
        return failure.allowsConstantSpeedFallback
    }

    private func steer(_ elapsed: Double) {
        if let target = voiceTargetOffset, tracker.isLocked {
            let delta = target - proxy.offsetY
            let smoothed = delta * (1 - exp(-catchUpRate * elapsed))
            // Catching up is capped so a late lock glides in instead of
            // whipping the page past you.
            let forwardLimit = pointsPerSecond * 4 * elapsed
            let backwardLimit = pointsPerSecond * 2 * elapsed
            proxy.offsetY += min(max(smoothed, -backwardLimit), forwardLimit)
        } else if tracker.isOffScript {
            // Talking, but not saying anything in the script. Keep drifting at
            // the configured pace rather than freezing mid-take.
            proxy.offsetY += pointsPerSecond * elapsed
        }
        // Otherwise hold: silence should stop the text, not run ahead of you.
    }
}
