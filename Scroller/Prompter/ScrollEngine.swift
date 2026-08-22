import QuartzCore

/// Frame-synced clock for the prompter. It only reports elapsed time; the
/// caller decides how far to move, so the scroll rate can be derived from the
/// current layout on every frame. Voice tracking will reuse this same tick.
@MainActor
final class ScrollEngine {
    var onTick: ((Double) -> Void)?

    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?

    var isRunning: Bool { displayLink != nil }

    func start() {
        guard displayLink == nil else { return }
        lastTimestamp = nil
        let link = CADisplayLink(
            target: DisplayLinkProxy(engine: self),
            selector: #selector(DisplayLinkProxy.tick(_:))
        )
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        lastTimestamp = nil
    }

    fileprivate func tick(at timestamp: CFTimeInterval) {
        defer { lastTimestamp = timestamp }
        guard let lastTimestamp else { return }
        // A dropped frame or a return from the background shouldn't lurch the text.
        let elapsed = min(timestamp - lastTimestamp, 1.0 / 20.0)
        onTick?(elapsed)
    }
}

/// CADisplayLink retains its target, so the engine is held weakly here to stop
/// the link outliving the view that owns it.
@MainActor
private final class DisplayLinkProxy: NSObject {
    private weak var engine: ScrollEngine?

    init(engine: ScrollEngine) {
        self.engine = engine
    }

    @objc func tick(_ link: CADisplayLink) {
        engine?.tick(at: link.timestamp)
    }
}
