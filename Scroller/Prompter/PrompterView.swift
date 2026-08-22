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

        GeometryReader { geometry in
            let readingLineY = geometry.size.height * settings.eyeLineFraction

            ZStack {
                Color.black

                PrompterTextView(
                    text: script.body,
                    fontSize: settings.fontSize,
                    isMirrored: settings.isMirrored,
                    topInset: readingLineY,
                    bottomInset: max(0, geometry.size.height - readingLineY),
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

                readingLine(width: geometry.size.width, height: geometry.size.height)

                if model.isActive {
                    runningHint
                } else {
                    controls(wordsPerMinute: $settings.wordsPerMinute)
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
        .ignoresSafeArea()
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

    private func readingLine(width: CGFloat, height: CGFloat) -> some View {
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
        .position(x: width / 2, y: height * settings.eyeLineFraction)
        .gesture(
            DragGesture()
                .onChanged { value in
                    settings.eyeLineFraction = min(max(value.location.y / height, 0.12), 0.78)
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
            } else {
                Text("Tap anywhere to stop")
            }
        }
        .font(.footnote.weight(.medium))
        .foregroundStyle(.white.opacity(0.4))
        .padding(.bottom, 36)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .allowsHitTesting(false)
    }

    private func controls(wordsPerMinute: Binding<Double>) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                iconButton("xmark") { dismiss() }
                Spacer()
                iconButton("waveform", isOn: settings.isVoiceTracking) {
                    settings.isVoiceTracking.toggle()
                }
                iconButton("arrow.counterclockwise") { model.restart() }
                iconButton("flip.horizontal", isOn: settings.isMirrored) {
                    settings.isMirrored.toggle()
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 60)

            Spacer()

            VStack(spacing: 20) {
                Button { model.start() } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(.black)
                        .frame(width: 74, height: 74)
                        .background(Color.scrollerAccent, in: .circle)
                }

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
            .padding(.horizontal, 34)
            .padding(.bottom, 44)
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
                .frame(height: 150)

                Spacer(minLength: 0)

                LinearGradient(
                    colors: [.black.opacity(0), .black.opacity(0.9), .black.opacity(0.98)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 290)
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
            .background(.ultraThinMaterial, in: .capsule)
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

    private func iconButton(_ symbol: String, isOn: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isOn ? .black : .white)
                .frame(width: 40, height: 40)
                .background(
                    isOn ? AnyShapeStyle(Color.scrollerAccent) : AnyShapeStyle(.ultraThinMaterial),
                    in: .circle
                )
        }
    }

    private var durationText: String {
        ReadingTime.clock(words: script.wordCount, wordsPerMinute: settings.wordsPerMinute)
    }
}
