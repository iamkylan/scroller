import SwiftUI
import UIKit

/// SwiftUI-facing view that hosts the TextKit 2 text view. UIKit owns the pinch
/// and tap recognizers rather than SwiftUI, so there's no gesture arbitration
/// against the scroll view underneath them.
struct PrompterTextView: UIViewRepresentable {
    let text: String
    let fontSize: Double
    let isMirrored: Bool
    let topInset: Double
    let bottomInset: Double
    let readingLineY: Double
    let proxy: PrompterTextProxy

    var onFontSizeChange: (Double) -> Void
    var onTap: () -> Void
    var onManualScroll: () -> Void

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView(usingTextLayoutManager: true)
        textView.isEditable = false
        textView.isSelectable = false
        textView.backgroundColor = .clear
        textView.showsVerticalScrollIndicator = false
        textView.alwaysBounceVertical = true
        textView.contentInsetAdjustmentBehavior = .never
        textView.textContainer.lineFragmentPadding = 0
        textView.delegate = context.coordinator

        let pinch = UIPinchGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePinch(_:))
        )
        textView.addGestureRecognizer(pinch)

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        textView.addGestureRecognizer(tap)

        proxy.attach(textView)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self

        var needsRelayout = false
        let roundedSize = fontSize.rounded()

        if coordinator.appliedText != text || coordinator.appliedFontSize != roundedSize {
            textView.attributedText = Self.attributedText(text, fontSize: roundedSize)
            coordinator.appliedText = text
            coordinator.appliedFontSize = roundedSize
            needsRelayout = true
        }

        let insets = UIEdgeInsets(top: topInset, left: 26, bottom: bottomInset, right: 26)
        if textView.textContainerInset != insets {
            textView.textContainerInset = insets
            needsRelayout = true
        }

        let mirror = isMirrored ? CGAffineTransform(scaleX: -1, y: 1) : .identity
        if textView.transform != mirror {
            textView.transform = mirror
        }

        guard needsRelayout else { return }

        // TextKit 2 lays out lazily, but contentSize has to be exact before we
        // can convert words-per-minute into a scroll rate or clamp the offset.
        textView.layoutIfNeeded()
        if let layoutManager = textView.textLayoutManager {
            layoutManager.ensureLayout(for: layoutManager.documentRange)
        }

        // Keep whatever word was on the reading line pinned there across a resize.
        if let anchor = coordinator.pinchAnchorIndex {
            proxy.scroll(characterIndex: anchor, toScreenY: readingLineY)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    private static func attributedText(_ text: String, fontSize: Double) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = 1.2
        paragraph.paragraphSpacing = fontSize * 0.55
        paragraph.alignment = .left
        paragraph.hyphenationFactor = 0

        return NSAttributedString(string: text, attributes: [
            .font: UIFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: UIColor.white,
            .paragraphStyle: paragraph,
        ])
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: PrompterTextView
        var appliedText: String?
        var appliedFontSize: Double?
        private(set) var pinchAnchorIndex: Int?
        private var pinchBaseFontSize: Double = 0

        init(parent: PrompterTextView) {
            self.parent = parent
        }

        @objc func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
            switch recognizer.state {
            case .began:
                pinchBaseFontSize = parent.fontSize
                pinchAnchorIndex = parent.proxy.characterIndex(atScreenY: parent.readingLineY)
            case .changed:
                let range = PrompterSettings.fontSizeRange
                let scaled = pinchBaseFontSize * Double(recognizer.scale)
                parent.onFontSizeChange(min(max(scaled, range.lowerBound), range.upperBound))
            case .ended, .cancelled, .failed:
                pinchAnchorIndex = nil
            default:
                break
            }
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            parent.onTap()
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            parent.onManualScroll()
        }
    }
}
