import UIKit

/// Imperative handle onto the laid-out text: lets the prompter ask "which word
/// is on the reading line right now?" and "put this word on the reading line".
/// Voice tracking will lean on exactly these two questions.
@MainActor
final class PrompterTextProxy {
    private weak var textView: UITextView?

    var offsetY: Double {
        get { Double(textView?.contentOffset.y ?? 0) }
        set {
            guard let textView else { return }
            textView.contentOffset.y = CGFloat(min(max(newValue, 0), maxOffsetY))
        }
    }

    var maxOffsetY: Double {
        guard let textView else { return 0 }
        return max(0, Double(textView.contentSize.height - textView.bounds.height))
    }

    /// Height of the text itself, excluding the reading-line padding. Used to
    /// convert words-per-minute into points-per-second.
    var textHeight: Double {
        guard let textView else { return 0 }
        let padding = textView.textContainerInset.top + textView.textContainerInset.bottom
        return max(1, Double(textView.contentSize.height - padding))
    }

    var hasReachedEnd: Bool {
        let limit = maxOffsetY
        return limit <= 0 || offsetY >= limit - 0.5
    }

    func characterIndex(atScreenY screenY: Double) -> Int? {
        guard let textView else { return nil }
        let point = CGPoint(x: textView.bounds.midX, y: textView.contentOffset.y + CGFloat(screenY))
        guard let position = textView.closestPosition(to: point) else { return nil }
        return textView.offset(from: textView.beginningOfDocument, to: position)
    }

    func scroll(characterIndex index: Int, toScreenY screenY: Double) {
        guard let rect = rect(forCharacterIndex: index) else { return }
        offsetY = Double(rect.minY) - screenY
    }

    private func rect(forCharacterIndex index: Int) -> CGRect? {
        guard let textView,
              let start = textView.position(from: textView.beginningOfDocument, offset: index)
        else { return nil }

        let end = textView.position(from: start, offset: 1) ?? start
        if let range = textView.textRange(from: start, to: end) {
            let rect = textView.firstRect(for: range)
            if !rect.isNull && rect.minY.isFinite { return rect }
        }
        let caret = textView.caretRect(for: start)
        return caret.minY.isFinite ? caret : nil
    }

    func attach(_ textView: UITextView) {
        self.textView = textView
    }
}
