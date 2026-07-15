import ARKit
import AVFoundation
import CoreGraphics
import Foundation
import Observation

@MainActor
protocol PoseTrackingProviding: AnyObject {
    var sample: PoseSample { get }
    var status: PoseTrackingStatus { get }
    var calibrationState: PoseCalibrationState { get }
    var cameraAccess: CameraAccessState { get }
    var latestGesture: PoseGestureEvent? { get }

    func start() async
    func stop()
    func beginCalibration()
    func resetCalibration()
}

/// SwiftUI/game-facing coordinator for permission, capture, calibration, safety, and gestures.
/// It intentionally has no API for obtaining or retaining camera frames.
@MainActor
@Observable
final class PoseTrackingService: PoseTrackingProviding {
    private(set) var sample: PoseSample = .neutral
    private(set) var status: PoseTrackingStatus = .idle
    private(set) var calibrationState: PoseCalibrationState = .notCalibrated
    private(set) var baseline: PoseBaseline?
    private(set) var cameraAccess: CameraAccessState
    private(set) var latestGesture: PoseGestureEvent?
    private(set) var recentGestures: [PoseGestureEvent] = []
    private(set) var lastAbruptMotion: AbruptMotionEvent?
    private(set) var configuration: PoseTrackingConfiguration

    /// Optional low-latency callback for SceneKit. SwiftUI can observe `latestGesture` instead.
    @ObservationIgnored var onGesture: ((PoseGestureEvent) -> Void)?

    @ObservationIgnored private let pipeline = PoseProcessingPipeline()
    @ObservationIgnored private var captureDriver: PoseCaptureDriver?
    @ObservationIgnored private var watchdogTask: Task<Void, Never>?
    @ObservationIgnored private var syntheticSequenceTask: Task<Void, Never>?
    @ObservationIgnored private var lifecycleGeneration = 0
    @ObservationIgnored private var syntheticSequence = 0
    @ObservationIgnored private var lastMeasurementTimestamp: TimeInterval?
    @ObservationIgnored private var hasReceivedMeasurement = false
    @ObservationIgnored private var activeSource: PoseTrackingSource?

    init(configuration: PoseTrackingConfiguration = .default) {
        var configuration = configuration
        configuration.sanitize()
        self.configuration = configuration
        self.cameraAccess = Self.currentCameraAccess()
    }

    func start() async {
        lifecycleGeneration &+= 1
        let generation = lifecycleGeneration
        shutDown(clearCalibration: true, setIdle: false)

        #if targetEnvironment(simulator)
        enableSyntheticInputInternal()
        #else
        status = .requestingPermission
        let access = await requestCameraAccess()
        guard lifecycleGeneration == generation else { return }

        guard access == .authorized else {
            status = access == .denied || access == .restricted
                ? .permissionDenied
                : .unavailable(reason: "A front-facing camera is unavailable.")
            return
        }

        startBestLiveDriver(generation: generation)
        #endif
    }

    func stop() {
        lifecycleGeneration &+= 1
        shutDown(clearCalibration: true, setIdle: true)
    }

    @discardableResult
    func requestCameraAccess() async -> CameraAccessState {
        let authorization = AVCaptureDevice.authorizationStatus(for: .video)
        switch authorization {
        case .authorized:
            cameraAccess = .authorized
        case .denied:
            cameraAccess = .denied
        case .restricted:
            cameraAccess = .restricted
        case .notDetermined:
            cameraAccess = .notDetermined
            let granted: Bool = await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    continuation.resume(returning: granted)
                }
            }
            cameraAccess = granted ? .authorized : .denied
        @unknown default:
            cameraAccess = .unavailable
        }
        return cameraAccess
    }

    func beginCalibration() {
        if activeSource == .synthetic {
            installBaseline(.syntheticNeutral)
            return
        }

        let now = ProcessInfo.processInfo.systemUptime
        baseline = nil
        pipeline.beginCalibration(at: now)
        calibrationState = .collecting(progress: 0, acceptedSamples: 0)
        sample.controlsAreSafe = false
    }

    func resetCalibration() {
        beginCalibration()
    }

    func cancelCalibration() {
        pipeline.cancelCalibration()
        if let baseline {
            calibrationState = .calibrated(baseline)
        } else {
            calibrationState = .notCalibrated
        }
    }

    func updateConfiguration(_ change: (inout PoseTrackingConfiguration) -> Void) {
        var updated = configuration
        change(&updated)
        updated.sanitize()
        configuration = updated
    }

    func setSensitivity(_ sensitivity: Double) {
        updateConfiguration { $0.sensitivity = sensitivity }
    }

    // MARK: - Simulator / touch hooks

    /// Switches away from live capture. Useful on Simulator, in previews, and in UI tests.
    func enableSyntheticInput() {
        lifecycleGeneration &+= 1
        shutDown(clearCalibration: true, setIdle: false)
        enableSyntheticInputInternal()
    }

    /// Re-enters the normal camera path after using synthetic controls on a physical device.
    func resumeLiveCamera() {
        Task { await start() }
    }

    func setSyntheticInput(_ input: SyntheticPoseInput) {
        ensureSyntheticInput()
        cancelSyntheticSequence()
        applySyntheticInput(input)
    }

    /// Maps a SwiftUI DragGesture's translation into a selected synthetic control channel.
    func updateSyntheticTouch(
        translation: CGSize,
        in bounds: CGSize,
        mapping: SyntheticTouchMapping = .steerAndNod
    ) {
        guard bounds.width.isFinite, bounds.height.isFinite,
              bounds.width > 1, bounds.height > 1 else {
            return
        }
        ensureSyntheticInput()
        cancelSyntheticSequence()

        let horizontal = min(max(Double(translation.width / (bounds.width * 0.32)), -1), 1)
        let vertical = min(max(Double(translation.height / (bounds.height * 0.24)), -1), 1)
        var input = SyntheticPoseInput.neutral
        switch mapping {
        case .steerAndNod:
            input.yaw = horizontal
            input.pitch = vertical
        case .sideBend:
            input.roll = horizontal
        case .retraction:
            input.retraction = max(0, -vertical)
        case .shoulderSet:
            input.shoulderSet = max(0, -vertical)
        }
        applySyntheticInput(input)
    }

    /// Call from DragGesture.onEnded. Repeated neutral samples rearm discrete gestures.
    func endSyntheticTouch() {
        ensureSyntheticInput()
        cancelSyntheticSequence()
        let sequence = syntheticSequence
        applySyntheticInput(.neutral)
        syntheticSequenceTask = Task { @MainActor [weak self] in
            guard await Self.wait(milliseconds: 220),
                  let self,
                  self.syntheticSequence == sequence else { return }
            self.applySyntheticInput(.neutral)
            guard await Self.wait(milliseconds: 220), self.syntheticSequence == sequence else { return }
            self.applySyntheticInput(.neutral)
        }
    }

    /// Deterministically crosses a recognizer threshold and then returns to neutral.
    func pulseSyntheticGesture(_ kind: PoseGestureKind) {
        ensureSyntheticInput()
        cancelSyntheticSequence()
        let sequence = syntheticSequence
        var peak = SyntheticPoseInput.neutral
        switch kind {
        case .nodDown: peak.pitch = 1
        case .nodUp: peak.pitch = -1
        case .retraction: peak.retraction = 1
        case .sideBendLeft: peak.roll = -1
        case .sideBendRight: peak.roll = 1
        case .shoulderSet: peak.shoulderSet = 1
        }
        applySyntheticInput(peak)

        syntheticSequenceTask = Task { @MainActor [weak self] in
            guard await Self.wait(milliseconds: 150),
                  let self,
                  self.syntheticSequence == sequence else { return }
            self.applySyntheticInput(.neutral)
            guard await Self.wait(milliseconds: 230), self.syntheticSequence == sequence else { return }
            self.applySyntheticInput(.neutral)
            guard await Self.wait(milliseconds: 230), self.syntheticSequence == sequence else { return }
            self.applySyntheticInput(.neutral)
        }
    }

    // MARK: - Live driver lifecycle

    private func startBestLiveDriver(generation: Int) {
        let bodyInterval = configuration.bodyPoseInterval
        if ARFaceTrackingConfiguration.isSupported {
            do {
                try startDriver(
                    ARKitFaceTrackingDriver(bodyPoseInterval: bodyInterval),
                    source: .arKitTrueDepth,
                    generation: generation
                )
                return
            } catch {
                // A Vision front-camera path remains available when ARKit cannot start.
            }
        }

        do {
            try startDriver(
                VisionFaceTrackingDriver(bodyPoseInterval: bodyInterval),
                source: .visionFrontCamera,
                generation: generation
            )
        } catch {
            activeSource = nil
            status = .failed(message: error.localizedDescription)
        }
    }

    private func startDriver(
        _ driver: PoseCaptureDriver,
        source: PoseTrackingSource,
        generation: Int
    ) throws {
        activeSource = source
        status = .starting(source)
        lastMeasurementTimestamp = ProcessInfo.processInfo.systemUptime
        hasReceivedMeasurement = false

        driver.onMeasurement = { [weak self] measurement in
            Task { @MainActor [weak self] in
                guard let self, self.lifecycleGeneration == generation else { return }
                self.receive(measurement)
            }
        }
        driver.onStateChange = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self, self.lifecycleGeneration == generation else { return }
                self.receive(state)
            }
        }
        captureDriver = driver
        do {
            try driver.start()
            startWatchdog(generation: generation)
        } catch {
            driver.stop()
            if captureDriver === driver { captureDriver = nil }
            throw error
        }
    }

    private func receive(_ raw: RawPoseMeasurement) {
        lastMeasurementTimestamp = raw.timestamp
        hasReceivedMeasurement = true

        switch calibrationState {
        case .collecting:
            handleCalibration(
                pipeline.consumeCalibration(raw, configuration: configuration)
            )
            sample = uncalibratedSample(from: raw)
            status = .tracking(raw.source)
            return
        case .notCalibrated, .failed:
            sample = uncalibratedSample(from: raw)
            status = .tracking(raw.source)
            return
        case .calibrated:
            break
        }

        guard let result = pipeline.process(raw, configuration: configuration) else {
            return
        }
        sample = result.sample
        if let abrupt = result.abruptMotion {
            lastAbruptMotion = abrupt
        }

        if result.safetyPauseEndsAt != nil {
            status = .pausedForAbruptMotion
        } else {
            status = .tracking(raw.source)
        }

        for event in result.gestures {
            latestGesture = event
            recentGestures.append(event)
            if recentGestures.count > 16 {
                recentGestures.removeFirst(recentGestures.count - 16)
            }
            onGesture?(event)
        }
    }

    private func receive(_ state: PoseCaptureDriverState) {
        switch state {
        case .running:
            if let activeSource {
                if case .pausedForAbruptMotion = status {
                    break
                }
                status = hasReceivedMeasurement ? .tracking(activeSource) : .starting(activeSource)
            }
        case .limited(let reason):
            status = .trackingLimited(reason: reason)
            sample.controlsAreSafe = false
        case .interrupted:
            status = .interrupted
            sample.controlsAreSafe = false
            if case .collecting = calibrationState {
                calibrationState = .failed(.trackingInterrupted)
            }
        case .failed(let message):
            status = .failed(message: message)
            sample.controlsAreSafe = false
            if case .collecting = calibrationState {
                calibrationState = .failed(.trackingInterrupted)
            }
        }
    }

    private func handleCalibration(_ update: CalibrationAccumulatorUpdate) {
        switch update {
        case .collecting(let progress, let samples):
            calibrationState = .collecting(progress: progress, acceptedSamples: samples)
        case .completed(let baseline):
            installBaseline(baseline)
        case .failed(let failure):
            pipeline.cancelCalibration()
            calibrationState = .failed(failure)
        }
    }

    private func installBaseline(_ baseline: PoseBaseline) {
        self.baseline = baseline
        pipeline.installBaseline(baseline)
        calibrationState = .calibrated(baseline)
        sample = PoseSample(
            timestamp: ProcessInfo.processInfo.systemUptime,
            yaw: 0,
            pitch: 0,
            roll: 0,
            retraction: 0,
            shoulderSet: 0,
            confidence: baseline.source == .synthetic ? 1 : sample.confidence,
            neutralAlignment: 1,
            motionSmoothness: 1,
            source: baseline.source,
            isAbruptMotion: false,
            controlsAreSafe: baseline.source == .synthetic
        )
    }

    // MARK: - Watchdog and safety recovery

    private func startWatchdog(generation: Int) {
        watchdogTask?.cancel()
        watchdogTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 200_000_000)
                } catch {
                    return
                }
                guard let self, self.lifecycleGeneration == generation else { return }
                self.checkWatchdog()
            }
        }
    }

    private func checkWatchdog() {
        let now = ProcessInfo.processInfo.systemUptime
        if case .collecting = calibrationState,
           let update = pipeline.calibrationTimeout(at: now, configuration: configuration) {
            handleCalibration(update)
        }

        if let safetyEnd = pipeline.safetyPauseEndsAt, now >= safetyEnd {
            pipeline.clearExpiredSafetyPause(at: now)
            if let activeSource,
               let lastMeasurementTimestamp,
               now - lastMeasurementTimestamp <= configuration.trackingLossDelay {
                sample.controlsAreSafe = sample.confidence >= configuration.minimumConfidence
                sample.isAbruptMotion = false
                status = .tracking(activeSource)
            }
        }

        guard activeSource != .synthetic,
              let lastMeasurementTimestamp,
              now - lastMeasurementTimestamp > configuration.trackingLossDelay else {
            return
        }
        switch status {
        case .interrupted, .failed, .permissionDenied, .unavailable:
            return
        default:
            status = .trackingLost
            sample.confidence = 0
            sample.controlsAreSafe = false
        }
    }

    // MARK: - Synthetic pipeline

    private func enableSyntheticInputInternal() {
        activeSource = .synthetic
        hasReceivedMeasurement = true
        status = .tracking(.synthetic)
        cameraAccess = Self.currentCameraAccess()
        installBaseline(.syntheticNeutral)
        recentGestures.removeAll()
        latestGesture = nil
        lastAbruptMotion = nil
        applySyntheticInput(.neutral)
    }

    private func ensureSyntheticInput() {
        guard activeSource != .synthetic else { return }
        enableSyntheticInput()
    }

    private func applySyntheticInput(_ input: SyntheticPoseInput) {
        let input = input.sanitized()
        let timestamp = ProcessInfo.processInfo.systemUptime
        let raw = RawPoseMeasurement(
            timestamp: timestamp,
            yawRadians: input.yaw,
            pitchRadians: input.pitch,
            rollRadians: input.roll,
            depthSignal: input.retraction,
            shoulderSignal: input.shoulderSet,
            faceConfidence: input.confidence,
            shoulderConfidence: input.confidence,
            source: .synthetic
        )
        lastMeasurementTimestamp = timestamp
        guard let result = pipeline.process(
            raw,
            configuration: configuration,
            valuesAreAlreadyNormalized: true
        ) else { return }
        sample = result.sample
        status = .tracking(.synthetic)
        for event in result.gestures {
            latestGesture = event
            recentGestures.append(event)
            if recentGestures.count > 16 {
                recentGestures.removeFirst(recentGestures.count - 16)
            }
            onGesture?(event)
        }
    }

    private func cancelSyntheticSequence() {
        syntheticSequence &+= 1
        syntheticSequenceTask?.cancel()
        syntheticSequenceTask = nil
    }

    private static func wait(milliseconds: UInt64) async -> Bool {
        do {
            try await Task.sleep(nanoseconds: milliseconds * 1_000_000)
            return !Task.isCancelled
        } catch {
            return false
        }
    }

    // MARK: - Helpers

    private func shutDown(clearCalibration: Bool, setIdle: Bool) {
        captureDriver?.stop()
        captureDriver = nil
        watchdogTask?.cancel()
        watchdogTask = nil
        syntheticSequenceTask?.cancel()
        syntheticSequenceTask = nil
        syntheticSequence &+= 1
        activeSource = nil
        lastMeasurementTimestamp = nil
        hasReceivedMeasurement = false
        recentGestures.removeAll()
        latestGesture = nil
        lastAbruptMotion = nil

        if clearCalibration {
            baseline = nil
            calibrationState = .notCalibrated
            pipeline.reset()
        }
        sample = .neutral
        if setIdle { status = .idle }
    }

    private func uncalibratedSample(from raw: RawPoseMeasurement) -> PoseSample {
        PoseSample(
            timestamp: raw.timestamp,
            yaw: 0,
            pitch: 0,
            roll: 0,
            retraction: 0,
            shoulderSet: 0,
            confidence: min(max(raw.faceConfidence, 0), 1),
            neutralAlignment: 1,
            motionSmoothness: 1,
            source: raw.source,
            isAbruptMotion: false,
            controlsAreSafe: false
        )
    }

    private static func currentCameraAccess() -> CameraAccessState {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined: .notDetermined
        case .authorized: .authorized
        case .denied: .denied
        case .restricted: .restricted
        @unknown default: .unavailable
        }
    }
}
