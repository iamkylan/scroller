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
            Color.black.ignoresSafeArea()

            // The content deliberately stays inside the safe area: in landscape
            // the sensor housing would otherwise clip the start of every line.
            GeometryReader { geometry in
                let isShort = geometry.size.height < 500

                ZStack {
                    tapZones
                    beats(isShort: isShort)
                    chrome(isShort: isShort)

                    VoiceBanner(status: tracker.status)
                        .animation(.easeOut(duration: 0.2), value: tracker.status)
                }
            }
        }
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

    private func beats(isShort: Bool) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            // In landscape the line you're about to say is worth more than the
            // one you've already delivered.
            if let previous = tracker.previousBeat, !isShort {
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
                .minimumScaleFactor(isShort ? 0.32 : 0.5)

            takeBadge
                .padding(.top, isShort ? 10 : 18)

            Spacer(minLength: 0)

            if let next = tracker.nextBeat {
                // Deliberately readable, not a hint: saying its first couple of
                // words is what advances the prompter.
                Text(next.text)
                    .font(.system(size: settings.lineFontSize * (isShort ? 0.42 : 0.55), weight: .medium))
                    .foregroundStyle(.white.opacity(0.42))
                    .lineLimit(isShort ? 2 : 4)
                    .minimumScaleFactor(0.6)
                    .padding(.bottom, isShort ? 4 : 16)
            }
        }
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, isShort ? 20 : 24)
        // Clears the chrome and the beat progress bar above it.
        .padding(.top, isShort ? 74 : 132)
        .padding(.bottom, isShort ? 14 : 40)
        .scaleEffect(x: settings.isMirrored ? -1 : 1, y: 1)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var takeBadge: some View {
        if tracker.takeCount > 0 {
            HStack(spacing: 7) {
                Circle()
                    .fill(tracker.isSpeaking ? Color.scrollerAccent : .white.opacity(0.25))
                    .frame(width: 6, height: 6)
                Text("Take \(tracker.takeCount)")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.5))
            .animation(.easeOut(duration: 0.25), value: tracker.isSpeaking)
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

    private func chrome(isShort: Bool) -> some View {
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
            .padding(.horizontal, isShort ? 6 : 14)
            .padding(.top, isShort ? 8 : 46)
            // The moment you start delivering, the controls get out of the way.
            // The progress bar stays: it's information, not a control.
            .opacity(tracker.isSpeaking ? 0 : 1)
            .allowsHitTesting(!tracker.isSpeaking)
            .animation(.easeOut(duration: 0.4), value: tracker.isSpeaking)

            beatProgress
                .padding(.horizontal, isShort ? 8 : 16)
                .padding(.top, isShort ? 10 : 18)

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
