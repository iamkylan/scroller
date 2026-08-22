import SwiftUI

/// Line mode: read a beat, look at the camera, deliver it, repeat as many times
/// as you like. Nothing moves until you start saying the next line.
struct LineView: View {
    let script: Script

    @Environment(PrompterSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    @State private var tracker = BeatTracker()
    @State private var pinchBaseSize: Double?

    var body: some View {
        @Bindable var settings = settings

        ZStack {
            Color.black

            tapZones
            beats
            chrome

            VoiceBanner(status: tracker.status)
                .animation(.easeOut(duration: 0.2), value: tracker.status)
        }
        .ignoresSafeArea()
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .gesture(pinch)
        .onAppear {
            tracker.load(script)
            UIApplication.shared.isIdleTimerDisabled = true
            if settings.isVoiceTracking {
                Task { await tracker.startListening(script: script) }
            }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            Task { await tracker.stopListening() }
        }
        .onChange(of: settings.isVoiceTracking) { _, enabled in
            Task {
                if enabled {
                    await tracker.startListening(script: script)
                } else {
                    await tracker.stopListening()
                }
            }
        }
    }

    // MARK: - Beats

    private var beats: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            if let previous = tracker.previousBeat {
                Text(previous.text)
                    .font(.system(size: settings.lineFontSize * 0.3, weight: .medium))
                    .foregroundStyle(.white.opacity(0.2))
                    .lineLimit(2)
                    .padding(.bottom, 26)
            }

            if let direction = tracker.currentBeat?.direction {
                Text(direction.uppercased())
                    .font(.system(size: 13, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(Color.scrollerAccent)
                    .padding(.bottom, 14)
            }

            Text(tracker.currentBeat?.text ?? script.body)
                .font(.system(size: settings.lineFontSize, weight: .semibold))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.55)

            takeBadge
                .padding(.top, 18)

            Spacer(minLength: 0)

            if let next = tracker.nextBeat {
                // Deliberately readable, not a hint: saying its first couple of
                // words is what advances the prompter.
                Text(next.text)
                    .font(.system(size: settings.lineFontSize * 0.55, weight: .medium))
                    .foregroundStyle(.white.opacity(0.42))
                    .lineLimit(4)
                    .padding(.bottom, 66)
            }
        }
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 28)
        .padding(.vertical, 76)
        .scaleEffect(x: settings.isMirrored ? -1 : 1, y: 1)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var takeBadge: some View {
        if tracker.takeCount > 0 {
            HStack(spacing: 7) {
                Circle()
                    .fill(tracker.isDelivering ? Color.scrollerAccent : .white.opacity(0.25))
                    .frame(width: 6, height: 6)
                Text("Take \(tracker.takeCount)")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.5))
            .animation(.easeOut(duration: 0.25), value: tracker.isDelivering)
        }
    }

    // MARK: - Controls

    /// Tapping is always available and never wrong: left third steps back,
    /// the rest advances.
    private var tapZones: some View {
        HStack(spacing: 0) {
            zone(chevron: "chevron.left", enabled: tracker.index > 0) { tracker.goBack() }
                .frame(maxWidth: .infinity)
            zone(chevron: "chevron.right", enabled: tracker.index + 1 < tracker.beatCount) { tracker.advance() }
                .frame(maxWidth: .infinity)
                .frame(maxWidth: .infinity)
        }
    }

    private func zone(chevron: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                Image(systemName: chevron)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(enabled ? 0.25 : 0.06))
                    .padding(.bottom, 30)
            }
            .onTapGesture(perform: action)
    }

    private var chrome: some View {
        VStack {
            HStack(spacing: 10) {
                PrompterIconButton(symbol: "xmark") { dismiss() }
                Spacer()
                Text("\(tracker.index + 1) / \(max(tracker.beatCount, 1))")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.4))
                Spacer()
                PrompterIconButton(symbol: "waveform", isOn: settings.isVoiceTracking) {
                    settings.isVoiceTracking.toggle()
                }
                PrompterIconButton(symbol: "flip.horizontal", isOn: settings.isMirrored) {
                    settings.isMirrored.toggle()
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 60)

            Spacer()
        }
    }

    private var pinch: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let base = pinchBaseSize ?? settings.lineFontSize
                pinchBaseSize = base
                let range = PrompterSettings.fontSizeRange
                settings.lineFontSize = min(max(base * value.magnification, range.lowerBound), range.upperBound)
            }
            .onEnded { _ in pinchBaseSize = nil }
    }
}
