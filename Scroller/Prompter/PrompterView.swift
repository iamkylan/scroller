import SwiftUI

struct PrompterView: View {
    let script: Script

    @Environment(PrompterSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    @State private var model: PrompterModel
    @State private var sizeHUDToken = 0
    @State private var showSizeHUD = false

    init(script: Script) {
        self.script = script
        _model = State(initialValue: PrompterModel(script: script))
    }

    var body: some View {
        @Bindable var settings = settings

        // The reader sits inside the safe area so it can report the insets;
        // only the text itself runs full-bleed, and it insets its own text
        // container past the sensor housing.
        GeometryReader { geometry in
            let insets = geometry.safeAreaInsets
            let fullHeight = geometry.size.height + insets.top + insets.bottom
            let readingLineY = fullHeight * settings.eyeLineFraction
            let isShort = fullHeight < 500

            ZStack {
                Color.black.ignoresSafeArea()

                PrompterTextView(
                    text: script.body,
                    fontSize: settings.fontSize,
                    isMirrored: settings.isMirrored,
                    topInset: readingLineY,
                    bottomInset: max(0, fullHeight - readingLineY),
                    horizontalInset: max(26, max(insets.leading, insets.trailing) + 10),
                    readingLineY: readingLineY,
                    proxy: model.proxy,
                    onFontSizeChange: { newSize in
                        settings.fontSize = newSize
                        showSizeHUD = true
                        sizeHUDToken += 1
                        model.refreshVoiceTarget()
                    },
                    onTap: { model.toggle() },
                    onManualScroll: { model.stop() }
                )
                .ignoresSafeArea()

                readingLine(
                    width: geometry.size.width,
                    fullHeight: fullHeight,
                    topInset: insets.top
                )

                if model.isActive {
                    runningHint
                } else {
                    controls(wordsPerMinute: $settings.wordsPerMinute, isShort: isShort)
                }

                voiceBanner

                if let countdown = model.countdown {
                    Text("\(countdown)")
                        .font(.system(size: 120, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.scrollerAccent)
                        .shadow(color: .black.opacity(0.7), radius: 24)
                        .allowsHitTesting(false)
                }

                sizeHUD
            }
            .onAppear { model.readingLineY = readingLineY }
            .onChange(of: readingLineY) { _, newValue in model.readingLineY = newValue }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear {
            model.wordsPerMinute = settings.wordsPerMinute
            model.mode = settings.isVoiceTracking ? .voice : .constant
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            model.stop()
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onChange(of: settings.wordsPerMinute) { _, newValue in
            model.wordsPerMinute = newValue
        }
        .onChange(of: settings.isVoiceTracking) { _, newValue in
            model.stop()
            model.mode = newValue ? .voice : .constant
        }
    }

    // MARK: - Reading line

    private func readingLine(width: CGFloat, fullHeight: CGFloat, topInset: CGFloat) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "arrowtriangle.right.fill")
            Rectangle()
                .fill(.white.opacity(0.12))
                .frame(height: 1)
            Image(systemName: "arrowtriangle.left.fill")
        }
        .font(.system(size: 13))
        .foregroundStyle(Color.scrollerAccent)
        .padding(.horizontal, 10)
        .frame(width: width, height: 44)
        .contentShape(Rectangle())
        .position(x: width / 2, y: fullHeight * settings.eyeLineFraction - topInset)
        .gesture(
            DragGesture()
                .onChanged { value in
                    let fraction = (value.location.y + topInset) / fullHeight
                    settings.eyeLineFraction = min(max(fraction, 0.12), 0.78)
                }
        )
        .allowsHitTesting(!model.isActive)
    }

    // MARK: - Overlays

    private var runningHint: some View {
        VStack {
            Spacer()
            if model.mode == .voice && !model.isUsingFallbackPace {
                HStack(spacing: 7) {
                    Circle()
                        .fill(model.tracker.isLocked ? Color.scrollerAccent : .white.opacity(0.3))
                        .frame(width: 7, height: 7)
                    Text(model.tracker.isLocked ? "Following you" : "Listening")
                }
                .animation(.easeOut(duration: 0.25), value: model.tracker.isLocked)
            }
        }
        .font(.footnote.weight(.medium))
        .foregroundStyle(.white.opacity(0.4))
        .padding(.bottom, 36)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .allowsHitTesting(false)
    }

    private func controls(wordsPerMinute: Binding<Double>, isShort: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                PrompterIconButton(symbol: "xmark") { dismiss() }
                Spacer()
                PrompterIconButton(symbol: "waveform", isOn: settings.isVoiceTracking) {
                    settings.isVoiceTracking.toggle()
                }
                PrompterIconButton(symbol: "arrow.counterclockwise") { model.restart() }
                PrompterIconButton(symbol: "flip.horizontal", isOn: settings.isMirrored) {
                    settings.isMirrored.toggle()
                }
            }
            .padding(.horizontal, isShort ? 6 : 14)
            .padding(.top, isShort ? 8 : 46)

            Spacer()

            VStack(spacing: isShort ? 12 : 20) {
                Button { model.start() } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: isShort ? 24 : 30))
                        .foregroundStyle(.black)
                        .frame(width: isShort ? 60 : 78, height: isShort ? 60 : 78)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.tint(.scrollerAccent).interactive(), in: .circle)

                HStack(spacing: 14) {
                    Image(systemName: "tortoise.fill")
                    Slider(value: wordsPerMinute, in: PrompterSettings.wordsPerMinuteRange)
                    Image(systemName: "hare.fill")
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.4))

                Text(settings.isVoiceTracking
                     ? "Voice tracking · \(Int(settings.wordsPerMinute)) wpm fallback"
                     : "\(Int(settings.wordsPerMinute)) wpm · \(durationText)")
                    .font(.caption.weight(.medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.45))
            }
            .padding(.horizontal, isShort ? 40 : 30)
            .padding(.bottom, isShort ? 10 : 30)
        }
        .background {
            // The text scrolls underneath the controls, so the scrim has to be
            // heavy enough that the buttons stay legible over any line of text.
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [.black.opacity(0.95), .black.opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: isShort ? 96 : 150)

                Spacer(minLength: 0)

                LinearGradient(
                    colors: [.black.opacity(0), .black.opacity(0.9), .black.opacity(0.98)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: isShort ? 190 : 290)
            }
            .allowsHitTesting(false)
        }
    }

    private var voiceBanner: some View {
        VoiceBanner(status: model.tracker.status)
            .animation(.easeOut(duration: 0.2), value: model.tracker.status)
    }

    private var sizeHUD: some View {
        Text("\(Int(settings.fontSize)) pt")
            .font(.caption.weight(.semibold).monospacedDigit())
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .glassEffect(.regular, in: .capsule)
            .opacity(showSizeHUD ? 1 : 0)
            .animation(.easeOut(duration: 0.18), value: showSizeHUD)
            .padding(.top, 62)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .allowsHitTesting(false)
            .task(id: sizeHUDToken) {
                guard showSizeHUD else { return }
                try? await Task.sleep(for: .seconds(1))
                showSizeHUD = false
            }
    }

    private var durationText: String {
        ReadingTime.clock(words: script.wordCount, wordsPerMinute: settings.wordsPerMinute)
    }
}
