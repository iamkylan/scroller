import SwiftUI

/// Surfaces the states voice tracking can be in that the user has to act on:
/// waiting on a model download, or a permission that was turned down.
struct VoiceBanner: View {
    let status: SpeechTranscription.Status

    @State private var isVisible = true

    var body: some View {
        Group {
            if let content, isVisible {
            VStack(spacing: 10) {
                if case .installingModel(let fraction) = status {
                    ProgressView(value: fraction)
                        .tint(.scrollerAccent)
                        .frame(width: 180)
                }

                Text(content.title)
                    .font(.subheadline.weight(.semibold))
                Text(content.detail)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)

                if content.offersSettings {
                    Button("Open Settings") {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                        UIApplication.shared.open(url)
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.borderedProminent)
                    .tint(.scrollerAccent)
                    .foregroundStyle(.black)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
            .frame(maxWidth: 320)
                .glassEffect(.regular, in: .rect(cornerRadius: 22))
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.25), value: isVisible)
        .task(id: status) {
            isVisible = true
            // Anything the user can act on stays up. Anything informational
            // gets out of the way — in Line mode it would otherwise sit on top
            // of the line you're trying to read.
            guard content?.offersSettings == false else { return }
            try? await Task.sleep(for: .seconds(5))
            isVisible = false
        }
    }

    private struct Content {
        let title: String
        let detail: String
        var offersSettings = false
    }

    private var content: Content? {
        switch status {
        case .idle, .listening:
            nil
        case .preparing:
            Content(title: "Getting ready", detail: "Warming up on-device recognition.")
        case .installingModel:
            Content(title: "Downloading the language model",
                    detail: "One-time download. It runs entirely on your phone afterwards.")
        case .failed(.microphoneDenied):
            Content(title: "Microphone access is off",
                    detail: "Scroller needs the mic to hear where you are in the script.",
                    offersSettings: true)
        case .failed(.speechDenied):
            Content(title: "Speech recognition is off",
                    detail: "Turn it on to let the text follow your voice.",
                    offersSettings: true)
        case .failed(.noSupportedLocale):
            Content(title: "Language not supported",
                    detail: "No on-device model matches this script. Scrolling at the fallback pace instead.")
        case .failed(.modelUnavailable):
            Content(title: "Language model unavailable",
                    detail: "The on-device model couldn't be loaded. Scrolling at the fallback pace instead.")
        case .failed(.other(let message)):
            Content(title: "Voice tracking stopped", detail: message)
        }
    }
}
