import SwiftUI

struct GameView: View {
    @Environment(AppModel.self) private var appModel
    let mode: GameMode

    var body: some View {
        GameSessionView(
            mode: mode,
            theme: appModel.profile.selectedTheme,
            reduceMotion: appModel.settings.reduceMotion
        )
    }
}

private struct GameSessionView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(GameCenterService.self) private var gameCenter
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    let mode: GameMode
    let theme: GameTheme
    let reduceMotion: Bool

    @State private var controller: GameSceneController
    @State private var tracker: PoseTrackingService
    @State private var soundscape = SoundscapeEngine()
    @State private var snapshot = GameSnapshot()
    @State private var isPaused = false
    @State private var showCalibration = true
    @State private var completed: CompletedRun?
    @State private var lastAbruptMotionID: UUID?
    @State private var isTrackingSafetyPaused = false

    init(mode: GameMode, theme: GameTheme, reduceMotion: Bool) {
        self.mode = mode
        self.theme = theme
        self.reduceMotion = reduceMotion
        _controller = State(initialValue: GameSceneController(mode: mode, theme: theme, reduceMotion: reduceMotion))
        _tracker = State(initialValue: PoseTrackingService())
        var initial = GameSnapshot()
        initial.duration = mode == .techNeck ? 180 : 90
        _snapshot = State(initialValue: initial)
    }

    var body: some View {
        ZStack {
            GameSceneView(controller: controller)
                .ignoresSafeArea()

            LinearGradient(
                colors: [.black.opacity(0.34), .clear, .black.opacity(0.26)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            GameHUD(
                snapshot: snapshot,
                mode: mode,
                source: tracker.sample.source,
                onPause: pause
            )

            if tracker.sample.source == .synthetic, !isPaused, completed == nil {
                SyntheticControlDeck(tracker: tracker, mode: mode)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if showCalibration, completed == nil {
                CalibrationOverlay(
                    tracker: tracker,
                    onReady: finishCalibration,
                    onRetry: retryCalibration,
                    onUseTouch: useTouchControls,
                    onExit: { dismiss() }
                )
            }

            if isTrackingSafetyPaused, !showCalibration, !isPaused, completed == nil {
                TrackingPauseOverlay(
                    status: tracker.status,
                    onRecalibrate: recalibrate,
                    onEnd: { controller.endFlight() }
                )
            }

            if isPaused, completed == nil {
                PauseOverlay(
                    onResume: resume,
                    onRecalibrate: recalibrate,
                    onEnd: { controller.endFlight() }
                )
            }

            if let completed {
                RunSummaryOverlay(completed: completed) {
                    dismiss()
                }
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .task { await startSession() }
        .onDisappear { stopSession() }
        .onChange(of: tracker.sample) { _, sample in
            updateInput(sample)
        }
        .onChange(of: tracker.lastAbruptMotion?.id) { _, id in
            guard let id, id != lastAbruptMotionID else { return }
            lastAbruptMotionID = id
            controller.trigger(.abruptMotion)
        }
        .onChange(of: tracker.calibrationState) { _, state in
            if state.isCalibrated {
                finishCalibration()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active, completed == nil {
                pause()
            }
        }
    }

    private func startSession() async {
        controller.setPaused(true)
        controller.onSnapshot = { next in
            snapshot = next
            if next.isFinished, completed == nil {
                completeRun()
            }
        }
        controller.onEvent = handle
        tracker.onGesture = { gesture in
            handle(gesture)
        }
        tracker.setSensitivity(appModel.settings.sensitivity)
        soundscape.start(musicEnabled: appModel.settings.musicEnabled)
        await tracker.start()

        if tracker.calibrationState.isCalibrated {
            finishCalibration()
        } else if tracker.cameraAccess != .denied && tracker.cameraAccess != .restricted {
            tracker.beginCalibration()
        }
    }

    private func stopSession() {
        controller.setPaused(true)
        tracker.stop()
        soundscape.stop()
    }

    private func updateInput(_ sample: PoseSample) {
        let safe = sample.controlsAreSafe || sample.source == .synthetic
        controller.setInput(GameControlInput(
            horizontal: safe ? sample.yaw : 0,
            vertical: safe && mode == .casual ? -sample.pitch : 0,
            neutralQuality: sample.neutralAlignment,
            motionSmoothness: sample.motionSmoothness,
            trackingQuality: sample.confidence,
            trackingAvailable: safe
        ))
        updateTrackingSafety(for: sample)
    }

    private func handle(_ gesture: PoseGestureEvent) {
        guard mode == .techNeck else { return }
        switch gesture.kind {
        case .nodDown:
            controller.trigger(.nod)
        case .nodUp:
            if mode == .techNeck { controller.trigger(.nod) }
        case .retraction:
            controller.trigger(.shieldBoost)
        case .sideBendLeft:
            controller.trigger(.rollLeft)
        case .sideBendRight:
            controller.trigger(.rollRight)
        case .shoulderSet:
            controller.trigger(.shoulderSet)
        }
    }

    private func handle(_ event: GameSceneEvent) {
        let effectsEnabled = appModel.settings.soundEffectsEnabled
        let hapticsEnabled = appModel.settings.hapticsEnabled
        switch event {
        case .pickup:
            soundscape.play(.pickup, enabled: effectsEnabled)
            HapticService.impact(.light, intensity: 0.45, enabled: hapticsEnabled)
        case .collision:
            soundscape.play(.collision, enabled: effectsEnabled)
            HapticService.notification(.warning, enabled: hapticsEnabled)
        case .nearMiss:
            HapticService.impact(.soft, intensity: 0.35, enabled: hapticsEnabled)
        case .boost:
            soundscape.play(.boost, enabled: effectsEnabled)
            HapticService.impact(.medium, intensity: 0.55, enabled: hapticsEnabled)
        case .roll:
            soundscape.play(.roll, enabled: effectsEnabled)
            HapticService.selection(enabled: hapticsEnabled)
        case .courseComplete:
            soundscape.play(.complete, enabled: effectsEnabled)
            HapticService.notification(.success, enabled: hapticsEnabled)
        }
    }

    private func finishCalibration() {
        guard tracker.calibrationState.isCalibrated else { return }
        withAnimation(.easeOut(duration: 0.35)) {
            showCalibration = false
        }
        isPaused = false
        isTrackingSafetyPaused = tracker.sample.source != .synthetic && !tracker.sample.controlsAreSafe
        controller.setPaused(isTrackingSafetyPaused)
    }

    private func useTouchControls() {
        tracker.enableSyntheticInput()
        finishCalibration()
    }

    private func recalibrate() {
        isPaused = false
        controller.setPaused(true)
        isTrackingSafetyPaused = false
        withAnimation { showCalibration = true }
        tracker.resetCalibration()
    }

    private func retryCalibration() {
        controller.setPaused(true)
        isTrackingSafetyPaused = false
        withAnimation { showCalibration = true }
        tracker.resetCalibration()
    }

    private func pause() {
        guard completed == nil else { return }
        isPaused = true
        controller.setPaused(true)
    }

    private func resume() {
        isPaused = false
        controller.setPaused(isTrackingSafetyPaused || showCalibration)
    }

    private func updateTrackingSafety(for sample: PoseSample) {
        guard sample.source != .synthetic, !showCalibration, completed == nil else {
            if sample.source == .synthetic, isTrackingSafetyPaused {
                isTrackingSafetyPaused = false
                if !isPaused { controller.setPaused(false) }
            }
            return
        }

        if !sample.controlsAreSafe {
            isTrackingSafetyPaused = true
            controller.setPaused(true)
        } else if isTrackingSafetyPaused {
            isTrackingSafetyPaused = false
            if !isPaused { controller.setPaused(false) }
        }
    }

    private func completeRun() {
        controller.setPaused(true)
        let usedCamera = tracker.sample.source != .synthetic
        let eligible = usedCamera
            && snapshot.trackingQuality >= 0.95
            && snapshot.smoothness >= 0.55
        let record = controller.makeRunRecord(
            usedCameraControls: usedCamera,
            leaderboardEligible: eligible
        )
        let points = appModel.record(record)
        completed = CompletedRun(record: record, pointsEarned: points)
        if record.leaderboardEligible {
            Task { await gameCenter.submit(score: record.score, mode: record.mode) }
        }
    }
}

private struct CompletedRun: Identifiable {
    let id = UUID()
    let record: RunRecord
    let pointsEarned: Int
}

private struct GameHUD: View {
    let snapshot: GameSnapshot
    let mode: GameMode
    let source: PoseTrackingSource
    let onPause: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Button(action: onPause) {
                    Image(systemName: "pause.fill")
                        .frame(width: 42, height: 42)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .accessibilityLabel("Pause flight")

                VStack(alignment: .leading, spacing: 3) {
                    Text("\(snapshot.score.formatted())")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                    Text("×\(snapshot.multiplier, specifier: "%.2f") flow")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(SlouchColor.teal)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    Text(timeString(snapshot.remaining))
                        .font(.system(size: 20, weight: .medium, design: .rounded).monospacedDigit())
                    Label(source == .synthetic ? "Touch demo" : "On-device", systemImage: source == .synthetic ? "hand.draw" : "lock.shield")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)

            HStack(spacing: 10) {
                MeterBar(value: snapshot.hull / 100, color: snapshot.hull < 30 ? SlouchColor.danger : SlouchColor.moonstone, label: "HULL")
                MeterBar(value: snapshot.energy / 100, color: SlouchColor.teal, label: "FLOW")
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)

            if mode == .techNeck {
                MovementCueView(cue: snapshot.cue, progress: snapshot.cueProgress)
                    .padding(.top, 18)
            }

            Spacer()

            if let message = snapshot.statusMessage {
                Label(message, systemImage: "sparkles")
                    .font(.footnote.weight(.medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 142)
            }
        }
        .foregroundStyle(SlouchColor.moonstone)
    }

    private func timeString(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval.rounded(.up)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private struct MeterBar: View {
    let value: Double
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 7) {
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .tracking(1.2)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.1))
                    Capsule()
                        .fill(color.gradient)
                        .frame(width: proxy.size.width * min(max(value, 0), 1))
                }
            }
            .frame(height: 4)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct MovementCueView: View {
    let cue: MovementCue
    let progress: Double

    var body: some View {
        HStack(spacing: 11) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.12), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: max(0.06, min(progress, 1)))
                    .stroke(SlouchColor.teal, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: cue.symbol)
                    .font(.system(size: 14, weight: .medium))
            }
            .frame(width: 35, height: 35)

            VStack(alignment: .leading, spacing: 2) {
                Text(cue.prompt)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                Text("Smooth and comfortable")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay { Capsule().stroke(.white.opacity(0.12)) }
    }
}

private struct SyntheticControlDeck: View {
    let tracker: PoseTrackingService
    let mode: GameMode

    var body: some View {
        VStack {
            Spacer()
            HStack(alignment: .bottom, spacing: 12) {
                GeometryReader { proxy in
                    ZStack {
                        Circle().fill(.white.opacity(0.07))
                        Circle().stroke(.white.opacity(0.15))
                        Image(systemName: "move.3d")
                            .foregroundStyle(.white.opacity(0.38))
                    }
                    .contentShape(Circle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                tracker.updateSyntheticTouch(
                                    translation: value.translation,
                                    in: proxy.size,
                                    mapping: .steerAndNod
                                )
                            }
                            .onEnded { _ in tracker.endSyntheticTouch() }
                    )
                }
                .frame(width: 104, height: 104)
                .accessibilityLabel("Steering pad")

                Spacer()

                if mode == .techNeck {
                    HStack(spacing: 9) {
                        ControlButton(symbol: "arrow.counterclockwise", label: "Roll left") {
                            tracker.pulseSyntheticGesture(.sideBendLeft)
                        }
                        ControlButton(symbol: "shield.lefthalf.filled", label: "Boost") {
                            tracker.pulseSyntheticGesture(.retraction)
                        }
                        ControlButton(symbol: "arrow.clockwise", label: "Roll right") {
                            tracker.pulseSyntheticGesture(.sideBendRight)
                        }
                    }
                } else {
                    Text("Drag to follow")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 42)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
        }
    }
}

private struct ControlButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 46, height: 46)
                .background(.ultraThinMaterial, in: Circle())
                .overlay { Circle().stroke(.white.opacity(0.14)) }
        }
        .accessibilityLabel(label)
    }
}

private struct CalibrationOverlay: View {
    let tracker: PoseTrackingService
    let onReady: () -> Void
    let onRetry: () -> Void
    let onUseTouch: () -> Void
    let onExit: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()

            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .stroke(.white.opacity(0.12), lineWidth: 4)
                    Circle()
                        .trim(from: 0, to: calibrationProgress)
                        .stroke(SlouchColor.teal, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: tracker.sample.source == .synthetic ? "hand.draw" : "face.smiling")
                        .font(.system(size: 29, weight: .light))
                }
                .frame(width: 74, height: 74)

                VStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 25, weight: .light, design: .rounded))
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Label("Phone upright and stationary", systemImage: "iphone.gen3")
                    Label("Face and upper shoulders visible", systemImage: "viewfinder")
                    Label("Processed only on this iPhone", systemImage: "lock.shield")
                }
                .font(.footnote)
                .frame(maxWidth: .infinity, alignment: .leading)

                actionButtons
            }
            .padding(24)
            .frame(maxWidth: 355)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 30).stroke(.white.opacity(0.14)) }
            .padding(20)
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        if case .failed = tracker.calibrationState {
            Button("Retry camera", action: onRetry)
                .buttonStyle(.borderedProminent)
                .tint(SlouchColor.teal)
            Button("Use touch demo", action: onUseTouch)
                .buttonStyle(.bordered)
            Button("Exit", action: onExit)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        } else {
            switch tracker.status {
            case .permissionDenied, .unavailable, .failed:
                Button("Use touch demo", action: onUseTouch)
                    .buttonStyle(.borderedProminent)
                    .tint(SlouchColor.teal)
                Button("Exit", action: onExit)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            default:
                if tracker.calibrationState.isCalibrated {
                    Button("Begin flight", action: onReady)
                        .buttonStyle(.borderedProminent)
                        .tint(SlouchColor.teal)
                } else {
                    Button("Use touch demo", action: onUseTouch)
                        .font(.footnote)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var calibrationProgress: Double {
        switch tracker.calibrationState {
        case .collecting(let progress, _): progress
        case .calibrated: 1
        default: 0.08
        }
    }

    private var title: String {
        switch tracker.calibrationState {
        case .collecting: "Find your neutral"
        case .calibrated: "Ready to glide"
        case .failed: "Let's try once more"
        case .notCalibrated: "Preparing camera"
        }
    }

    private var message: String {
        switch tracker.calibrationState {
        case .collecting: "Sit or stand tall, relax your shoulders, and look comfortably at the screen."
        case .calibrated: "Your comfortable center is set for this flight."
        case .failed(let failure): failure.message
        case .notCalibrated:
            switch tracker.status {
            case .permissionDenied: "Camera access is off. You can enable it in Settings or use the touch demo."
            case .unavailable(let reason), .failed(let reason): reason
            default: "The camera will measure movement locally without saving video."
            }
        }
    }
}

private struct TrackingPauseOverlay: View {
    let status: PoseTrackingStatus
    let onRecalibrate: () -> Void
    let onEnd: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.58).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: isAbruptMotion ? "figure.cooldown" : "viewfinder")
                    .font(.system(size: 42, weight: .ultraLight))
                    .foregroundStyle(SlouchColor.teal)
                Text(isAbruptMotion ? "Movement paused" : "Tracking paused")
                    .font(.system(size: 25, weight: .light, design: .rounded))
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                ProgressView()
                    .tint(SlouchColor.teal)
                Button("Recalibrate camera", action: onRecalibrate)
                    .buttonStyle(.bordered)
                Button("End flight", role: .destructive, action: onEnd)
                    .font(.footnote)
            }
            .padding(26)
            .frame(maxWidth: 340)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 30).stroke(.white.opacity(0.14)) }
            .padding(24)
        }
    }

    private var isAbruptMotion: Bool {
        if case .pausedForAbruptMotion = status { return true }
        return false
    }

    private var message: String {
        switch status {
        case .pausedForAbruptMotion:
            "Settle into a comfortable neutral. The course will resume only when control is steady again."
        case .trackingLimited(let reason):
            reason
        case .trackingLost, .interrupted:
            "Return your face to the frame and hold comfortably still. Hazards and the timer are frozen."
        default:
            "Hold a comfortable neutral while Slouch restores a reliable control signal."
        }
    }
}

private struct PauseOverlay: View {
    let onResume: () -> Void
    let onRecalibrate: () -> Void
    let onEnd: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "pause.circle")
                    .font(.system(size: 48, weight: .ultraLight))
                    .foregroundStyle(SlouchColor.teal)
                Text("Take a breath")
                    .font(.system(size: 27, weight: .light, design: .rounded))
                Text("The course is frozen. Resume whenever you feel ready.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Resume", action: onResume)
                    .buttonStyle(.borderedProminent)
                    .tint(SlouchColor.teal)
                Button("Recalibrate camera", action: onRecalibrate)
                    .buttonStyle(.bordered)
                Button("End flight", role: .destructive, action: onEnd)
                    .font(.footnote)
            }
            .padding(26)
            .frame(maxWidth: 340)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            .padding(24)
        }
    }
}

private struct RunSummaryOverlay: View {
    let completed: CompletedRun
    let onDone: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.58).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 22) {
                    Image(systemName: completed.record.completedCourse ? "sparkles" : "moon.stars")
                        .font(.system(size: 44, weight: .ultraLight))
                        .foregroundStyle(SlouchColor.teal)

                    VStack(spacing: 6) {
                        Text(completed.record.completedCourse ? "Journey complete" : "Flight complete")
                            .font(.system(size: 28, weight: .light, design: .rounded))
                        Text("\(completed.record.score.formatted()) points")
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                    }

                    HStack(spacing: 10) {
                        SummaryMetric(value: "\(completed.record.metrics.controlledMovements)", label: "MOVES")
                        SummaryMetric(value: completed.record.metrics.neutralAccuracy.formatted(.percent.precision(.fractionLength(0))), label: "NEUTRAL")
                        SummaryMetric(value: completed.record.metrics.smoothness.formatted(.percent.precision(.fractionLength(0))), label: "SMOOTH")
                    }

                    HStack {
                        Label("+\(completed.pointsEarned) star fragments", systemImage: "sparkle")
                            .foregroundStyle(SlouchColor.solarGold)
                        Spacer()
                        Label(completed.record.leaderboardEligible ? "Ranked" : "Local score", systemImage: completed.record.leaderboardEligible ? "trophy" : "iphone")
                            .foregroundStyle(.secondary)
                    }
                    .font(.footnote.weight(.medium))
                    .padding(14)
                    .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 16))

                    Text("These are gameplay movement metrics, not a medical posture assessment.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Button("Return to observatory", action: onDone)
                        .buttonStyle(.borderedProminent)
                        .tint(SlouchColor.teal)
                }
                .padding(26)
            }
            .frame(maxWidth: 370, maxHeight: 560)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 30).stroke(.white.opacity(0.14)) }
            .padding(20)
        }
    }
}

private struct SummaryMetric: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 5) {
            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .tracking(1.1)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 13)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 16))
    }
}

private extension MovementCue {
    var symbol: String {
        switch self {
        case .neutral: "circle.dotted.circle"
        case .steerLeft: "arrow.turn.up.left"
        case .steerRight: "arrow.turn.up.right"
        case .nod: "arrow.down"
        case .retract: "shield.lefthalf.filled"
        case .bendLeft: "arrow.counterclockwise"
        case .bendRight: "arrow.clockwise"
        case .shoulderSet: "figure.arms.open"
        }
    }
}
