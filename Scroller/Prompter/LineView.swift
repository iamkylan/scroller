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
                    .padding(.bottom, 16)
            }
        }
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 28)
        // Clears the chrome and the beat progress bar above it.
        .padding(.top, 150)
        .padding(.bottom, 52)
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

    /// The screen itself is the control: left half steps back, right half
    /// advances. No arrows — the progress bar already says where you are.
    private var tapZones: some View {
        HStack(spacing: 0) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { tracker.goBack() }
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { tracker.advance() }
        }
    }

    /// One segment per beat: position and length at a glance, without a number
    /// to read or a control to press.
    private var beatProgress: some View {
        HStack(spacing: 3) {
            ForEach(0..<max(tracker.beatCount, 1), id: \.self) { beat in
                Capsule()
                    .fill(segmentStyle(for: beat))
                    .frame(height: 3)
            }
        }
        .animation(.easeOut(duration: 0.25), value: tracker.index)
    }

    private func segmentStyle(for beat: Int) -> Color {
        if beat == tracker.index { Color.scrollerAccent }
        else if beat < tracker.index { .white.opacity(0.3) }
        else { .white.opacity(0.1) }
    }

    private var chrome: some View {
        VStack {
            HStack(spacing: 10) {
                PrompterIconButton(symbol: "xmark") { dismiss() }
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

            beatProgress
                .padding(.horizontal, 20)
                .padding(.top, 18)

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
