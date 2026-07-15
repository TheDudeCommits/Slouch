import Foundation

/// A short-lived, numeric-only measurement. No image or landmark data crosses this boundary.
struct RawPoseMeasurement: Sendable {
    var timestamp: TimeInterval
    var yawRadians: Double
    var pitchRadians: Double
    var rollRadians: Double
    /// A dimensionless value whose increase means the face moved farther from the camera.
    var depthSignal: Double
    var shoulderSignal: Double?
    var faceConfidence: Double
    var shoulderConfidence: Double
    var source: PoseTrackingSource
}

enum CalibrationAccumulatorUpdate {
    case collecting(progress: Double, acceptedSamples: Int)
    case completed(PoseBaseline)
    case failed(PoseCalibrationFailure)
}

struct PoseProcessingResult {
    var sample: PoseSample
    var gestures: [PoseGestureEvent]
    var abruptMotion: AbruptMotionEvent?
    var safetyPauseEndsAt: TimeInterval?
}

/// Converts camera-specific radians/proxies into stable, calibrated game controls.
final class PoseProcessingPipeline {
    private var baseline: PoseBaseline?
    private var calibrator = CalibrationAccumulator()
    private var yawFilter = OneEuroFilter(minCutoff: 1.35, beta: 0.055)
    private var pitchFilter = OneEuroFilter(minCutoff: 1.2, beta: 0.05)
    private var rollFilter = OneEuroFilter(minCutoff: 1.2, beta: 0.05)
    private var depthFilter = OneEuroFilter(minCutoff: 1.0, beta: 0.035)
    private var shoulderFilter = OneEuroFilter(minCutoff: 0.75, beta: 0.02)
    private var confidenceFilter = OneEuroFilter(minCutoff: 0.8, beta: 0)
    private var previousRaw: RawPoseMeasurement?
    private var previousSmoothed: PoseSample?
    private var gestures = PoseGestureRecognizerSuite()
    private(set) var safetyPauseEndsAt: TimeInterval?

    func beginCalibration(at timestamp: TimeInterval) {
        calibrator.begin(at: timestamp)
        baseline = nil
        resetDynamicState()
    }

    func cancelCalibration() {
        calibrator.reset()
    }

    func consumeCalibration(
        _ measurement: RawPoseMeasurement,
        configuration: PoseTrackingConfiguration
    ) -> CalibrationAccumulatorUpdate {
        calibrator.consume(measurement, configuration: configuration)
    }

    func calibrationTimeout(
        at timestamp: TimeInterval,
        configuration: PoseTrackingConfiguration
    ) -> CalibrationAccumulatorUpdate? {
        calibrator.timeoutUpdate(at: timestamp, configuration: configuration)
    }

    func installBaseline(_ baseline: PoseBaseline?) {
        self.baseline = baseline
        calibrator.reset()
        resetDynamicState()
    }

    func reset() {
        baseline = nil
        calibrator.reset()
        resetDynamicState()
    }

    func process(
        _ raw: RawPoseMeasurement,
        configuration: PoseTrackingConfiguration,
        valuesAreAlreadyNormalized: Bool = false
    ) -> PoseProcessingResult? {
        guard let baseline, baseline.source == raw.source else { return nil }
        clearExpiredSafetyPause(at: raw.timestamp)

        let yawTarget: Double
        let pitchTarget: Double
        let rollTarget: Double
        let retractionTarget: Double
        let shoulderTarget: Double

        if valuesAreAlreadyNormalized {
            yawTarget = clamp(raw.yawRadians)
            pitchTarget = clamp(raw.pitchRadians)
            rollTarget = clamp(raw.rollRadians)
            retractionTarget = clamp(raw.depthSignal)
            shoulderTarget = clamp(raw.shoulderSignal ?? 0)
        } else {
            let sensitivity = configuration.sensitivity
            yawTarget = clamp(
                shortestAngle(raw.yawRadians - baseline.yawRadians)
                    / degreesToRadians(configuration.yawRangeDegrees)
                    * sensitivity
            )
            pitchTarget = clamp(
                shortestAngle(raw.pitchRadians - baseline.pitchRadians)
                    / degreesToRadians(configuration.pitchRangeDegrees)
                    * sensitivity
            )
            rollTarget = clamp(
                shortestAngle(raw.rollRadians - baseline.rollRadians)
                    / degreesToRadians(configuration.rollRangeDegrees)
                    * sensitivity
            )
            // Each driver pre-scales depth so a change of roughly one is a full retraction.
            retractionTarget = clamp((raw.depthSignal - baseline.depthSignal) * sensitivity)
            if let shoulder = raw.shoulderSignal, let baselineShoulder = baseline.shoulderSignal {
                shoulderTarget = clamp(
                    (shoulder - baselineShoulder)
                        / configuration.shoulderRange
                        * sensitivity
                )
            } else {
                shoulderTarget = 0
            }
        }

        let motion = valuesAreAlreadyNormalized
            ? syntheticMotionAnalysis(for: raw)
            : motionAnalysis(for: raw, configuration: configuration)
        if motion.isAbrupt {
            safetyPauseEndsAt = max(
                safetyPauseEndsAt ?? 0,
                raw.timestamp + configuration.abruptMotionPause
            )
        }
        let isSafetyPaused = (safetyPauseEndsAt ?? 0) > raw.timestamp

        let yaw = yawFilter.filter(yawTarget, timestamp: raw.timestamp)
        let pitch = pitchFilter.filter(pitchTarget, timestamp: raw.timestamp)
        let roll = rollFilter.filter(rollTarget, timestamp: raw.timestamp)
        let retraction = depthFilter.filter(retractionTarget, timestamp: raw.timestamp)
        let shoulder = shoulderFilter.filter(shoulderTarget, timestamp: raw.timestamp)

        let shoulderWeight = raw.shoulderSignal == nil ? 0.0 : 0.08
        let combinedConfidence = raw.faceConfidence * (1 - shoulderWeight)
            + raw.shoulderConfidence * shoulderWeight
        let confidence = clamp01(
            confidenceFilter.filter(combinedConfidence, timestamp: raw.timestamp)
        )

        let neutralMagnitude = max(
            abs(yaw),
            abs(pitch),
            abs(roll),
            abs(retraction),
            abs(shoulder) * 0.8
        )
        let neutralAlignment = clamp01(1 - neutralMagnitude * 1.15)
        let controlsAreSafe = confidence >= configuration.minimumConfidence && !isSafetyPaused

        var sample = PoseSample(
            timestamp: raw.timestamp,
            yaw: yaw,
            pitch: pitch,
            roll: roll,
            retraction: retraction,
            shoulderSet: shoulder,
            confidence: confidence,
            neutralAlignment: neutralAlignment,
            motionSmoothness: motion.smoothness,
            source: raw.source,
            isAbruptMotion: motion.isAbrupt,
            controlsAreSafe: controlsAreSafe
        )

        // During a safety pause, hold the last stable control vector. The game can pause
        // immediately from `controlsAreSafe` without receiving a second sudden movement.
        if isSafetyPaused, let previousSmoothed {
            sample.yaw = previousSmoothed.yaw
            sample.pitch = previousSmoothed.pitch
            sample.roll = previousSmoothed.roll
            sample.retraction = previousSmoothed.retraction
            sample.shoulderSet = previousSmoothed.shoulderSet
            sample.neutralAlignment = previousSmoothed.neutralAlignment
        } else {
            previousSmoothed = sample
        }

        let events = gestures.update(sample: sample, allowTrigger: controlsAreSafe)
        previousRaw = raw

        let abruptEvent = motion.isAbrupt
            ? AbruptMotionEvent(
                timestamp: raw.timestamp,
                angularVelocity: motion.angularVelocityDegreesPerSecond
            )
            : nil

        return PoseProcessingResult(
            sample: sample,
            gestures: events,
            abruptMotion: abruptEvent,
            safetyPauseEndsAt: safetyPauseEndsAt
        )
    }

    func clearExpiredSafetyPause(at timestamp: TimeInterval) {
        guard let end = safetyPauseEndsAt, timestamp >= end else { return }
        safetyPauseEndsAt = nil
    }

    private func resetDynamicState() {
        yawFilter.reset()
        pitchFilter.reset()
        rollFilter.reset()
        depthFilter.reset()
        shoulderFilter.reset()
        confidenceFilter.reset()
        previousRaw = nil
        previousSmoothed = nil
        gestures.reset()
        safetyPauseEndsAt = nil
    }

    private func motionAnalysis(
        for raw: RawPoseMeasurement,
        configuration: PoseTrackingConfiguration
    ) -> (isAbrupt: Bool, angularVelocityDegreesPerSecond: Double, smoothness: Double) {
        guard let previousRaw else {
            return (false, 0, 1)
        }

        let delta = raw.timestamp - previousRaw.timestamp
        // Do not interpret a reacquisition jump as a deliberate rapid movement.
        guard delta >= 1.0 / 240.0, delta <= 0.22 else {
            return (false, 0, 0.8)
        }

        let angularVelocity = max(
            abs(shortestAngle(raw.yawRadians - previousRaw.yawRadians)),
            abs(shortestAngle(raw.pitchRadians - previousRaw.pitchRadians)),
            abs(shortestAngle(raw.rollRadians - previousRaw.rollRadians))
        ) / delta * 180 / .pi
        let depthVelocity = abs(raw.depthSignal - previousRaw.depthSignal) / delta
        let isAbrupt = angularVelocity >= configuration.abruptAngularVelocityDegreesPerSecond
            || depthVelocity >= configuration.abruptDepthVelocity

        let comfortableAngularVelocity = 48.0
        let smoothness = clamp01(1 / (1 + pow(angularVelocity / comfortableAngularVelocity, 2)))
        return (isAbrupt, angularVelocity, isAbrupt ? 0 : smoothness)
    }

    private func syntheticMotionAnalysis(
        for raw: RawPoseMeasurement
    ) -> (isAbrupt: Bool, angularVelocityDegreesPerSecond: Double, smoothness: Double) {
        guard let previousRaw else { return (false, 0, 1) }
        let delta = raw.timestamp - previousRaw.timestamp
        guard delta > 0, delta <= 0.5 else { return (false, 0, 1) }
        let normalizedVelocity = max(
            abs(raw.yawRadians - previousRaw.yawRadians),
            abs(raw.pitchRadians - previousRaw.pitchRadians),
            abs(raw.rollRadians - previousRaw.rollRadians)
        ) / delta
        return (false, 0, clamp01(1 / (1 + pow(normalizedVelocity / 5, 2))))
    }
}

private struct CalibrationAccumulator {
    private var startedAt: TimeInterval?
    private var samples: [RawPoseMeasurement] = []

    mutating func begin(at timestamp: TimeInterval) {
        startedAt = timestamp
        samples.removeAll(keepingCapacity: true)
    }

    mutating func reset() {
        startedAt = nil
        samples.removeAll(keepingCapacity: true)
    }

    mutating func consume(
        _ measurement: RawPoseMeasurement,
        configuration: PoseTrackingConfiguration
    ) -> CalibrationAccumulatorUpdate {
        guard let startedAt else {
            return .failed(.trackingInterrupted)
        }

        if measurement.faceConfidence >= configuration.minimumConfidence {
            samples.append(measurement)
        }

        let elapsed = max(0, measurement.timestamp - startedAt)
        let progress = min(elapsed / configuration.calibrationDuration, 0.98)
        let recent = recentSamples(
            endingAt: measurement.timestamp,
            duration: configuration.calibrationDuration
        )
        let minimumSamples = max(12, Int(configuration.calibrationDuration * 12))

        if elapsed >= configuration.calibrationDuration,
           recent.count >= minimumSamples,
           let baseline = stableBaseline(from: recent) {
            return .completed(baseline)
        }

        if elapsed >= configuration.calibrationTimeout {
            if samples.isEmpty { return .failed(.faceNotVisible) }
            if recent.count < minimumSamples { return .failed(.lowConfidence) }
            return .failed(.movementTooLarge)
        }

        // Bound memory even if callers use a long custom timeout.
        if samples.count > 360 {
            samples.removeFirst(samples.count - 360)
        }
        return .collecting(progress: progress, acceptedSamples: recent.count)
    }

    func timeoutUpdate(
        at timestamp: TimeInterval,
        configuration: PoseTrackingConfiguration
    ) -> CalibrationAccumulatorUpdate? {
        guard let startedAt, timestamp - startedAt >= configuration.calibrationTimeout else {
            return nil
        }
        return samples.isEmpty ? .failed(.faceNotVisible) : .failed(.lowConfidence)
    }

    private func recentSamples(endingAt timestamp: TimeInterval, duration: TimeInterval) -> [RawPoseMeasurement] {
        samples.filter { timestamp - $0.timestamp <= duration }
    }

    private func stableBaseline(from values: [RawPoseMeasurement]) -> PoseBaseline? {
        let yaw = values.map(\.yawRadians)
        let pitch = values.map(\.pitchRadians)
        let roll = values.map(\.rollRadians)
        let depth = values.map(\.depthSignal)

        let maximumAngularDeviation = degreesToRadians(2.4)
        guard standardDeviation(yaw) <= maximumAngularDeviation,
              standardDeviation(pitch) <= maximumAngularDeviation,
              standardDeviation(roll) <= maximumAngularDeviation,
              standardDeviation(depth) <= 0.2,
              let source = values.last?.source else {
            return nil
        }

        let shoulderValues = values.compactMap(\.shoulderSignal)
        let shoulderBaseline = shoulderValues.count >= max(4, values.count / 5)
            ? median(shoulderValues)
            : nil

        return PoseBaseline(
            yawRadians: median(yaw),
            pitchRadians: median(pitch),
            rollRadians: median(roll),
            depthSignal: median(depth),
            shoulderSignal: shoulderBaseline,
            source: source,
            capturedAt: .now,
            sampleCount: values.count
        )
    }
}

private struct OneEuroFilter {
    let minCutoff: Double
    let beta: Double
    private let derivativeCutoff = 1.0
    private var previousRaw: Double?
    private var previousFiltered: Double?
    private var previousDerivative = 0.0
    private var previousTimestamp: TimeInterval?

    init(minCutoff: Double, beta: Double) {
        self.minCutoff = minCutoff
        self.beta = beta
    }

    mutating func filter(_ value: Double, timestamp: TimeInterval) -> Double {
        guard let previousRaw, let previousFiltered, let previousTimestamp else {
            self.previousRaw = value
            self.previousFiltered = value
            self.previousTimestamp = timestamp
            return value
        }

        let delta = min(max(timestamp - previousTimestamp, 1.0 / 240.0), 0.2)
        let rawDerivative = (value - previousRaw) / delta
        let derivativeAlpha = smoothingFactor(delta: delta, cutoff: derivativeCutoff)
        let filteredDerivative = derivativeAlpha * rawDerivative
            + (1 - derivativeAlpha) * previousDerivative
        let cutoff = minCutoff + beta * abs(filteredDerivative)
        let valueAlpha = smoothingFactor(delta: delta, cutoff: cutoff)
        let filtered = valueAlpha * value + (1 - valueAlpha) * previousFiltered

        self.previousRaw = value
        self.previousFiltered = filtered
        self.previousDerivative = filteredDerivative
        self.previousTimestamp = timestamp
        return filtered
    }

    mutating func reset() {
        previousRaw = nil
        previousFiltered = nil
        previousDerivative = 0
        previousTimestamp = nil
    }

    private func smoothingFactor(delta: TimeInterval, cutoff: Double) -> Double {
        let timeConstant = 1 / (2 * Double.pi * cutoff)
        return 1 / (1 + timeConstant / delta)
    }
}

private struct PoseGestureRecognizerSuite {
    private var nod = BidirectionalNeutralRecognizer(
        activationThreshold: 0.42,
        neutralThreshold: 0.16,
        neutralHold: 0.18,
        negativeKind: .nodUp,
        positiveKind: .nodDown
    )
    private var sideBend = BidirectionalNeutralRecognizer(
        activationThreshold: 0.52,
        neutralThreshold: 0.18,
        neutralHold: 0.2,
        negativeKind: .sideBendLeft,
        positiveKind: .sideBendRight
    )
    private var retraction = PositiveNeutralRecognizer(
        activationThreshold: 0.5,
        neutralThreshold: 0.16,
        neutralHold: 0.22,
        kind: .retraction
    )
    private var shoulderSet = PositiveNeutralRecognizer(
        activationThreshold: 0.55,
        neutralThreshold: 0.2,
        neutralHold: 0.25,
        kind: .shoulderSet
    )

    mutating func update(sample: PoseSample, allowTrigger: Bool) -> [PoseGestureEvent] {
        var events: [PoseGestureEvent] = []

        if let event = nod.update(
            value: sample.pitch,
            timestamp: sample.timestamp,
            allowTrigger: allowTrigger && abs(sample.yaw) < 0.45 && abs(sample.roll) < 0.45
        ) {
            events.append(event)
        }
        if let event = sideBend.update(
            value: sample.roll,
            timestamp: sample.timestamp,
            allowTrigger: allowTrigger && abs(sample.yaw) < 0.5
        ) {
            events.append(event)
        }
        if let event = retraction.update(
            value: sample.retraction,
            timestamp: sample.timestamp,
            allowTrigger: allowTrigger
                && abs(sample.pitch) < 0.38
                && abs(sample.roll) < 0.4
                && abs(sample.shoulderSet) < 0.45
        ) {
            events.append(event)
        }
        if let event = shoulderSet.update(
            value: sample.shoulderSet,
            timestamp: sample.timestamp,
            allowTrigger: allowTrigger && abs(sample.pitch) < 0.45 && abs(sample.roll) < 0.45
        ) {
            events.append(event)
        }
        return events
    }

    mutating func reset() {
        nod.reset()
        sideBend.reset()
        retraction.reset()
        shoulderSet.reset()
    }
}

private struct BidirectionalNeutralRecognizer {
    private enum State {
        case armed
        case waitingForNeutral(since: TimeInterval?)
    }

    let activationThreshold: Double
    let neutralThreshold: Double
    let neutralHold: TimeInterval
    let negativeKind: PoseGestureKind
    let positiveKind: PoseGestureKind
    private var state: State = .armed

    init(
        activationThreshold: Double,
        neutralThreshold: Double,
        neutralHold: TimeInterval,
        negativeKind: PoseGestureKind,
        positiveKind: PoseGestureKind
    ) {
        self.activationThreshold = activationThreshold
        self.neutralThreshold = neutralThreshold
        self.neutralHold = neutralHold
        self.negativeKind = negativeKind
        self.positiveKind = positiveKind
    }

    mutating func update(
        value: Double,
        timestamp: TimeInterval,
        allowTrigger: Bool
    ) -> PoseGestureEvent? {
        switch state {
        case .armed:
            guard allowTrigger, abs(value) >= activationThreshold else { return nil }
            state = .waitingForNeutral(since: nil)
            return PoseGestureEvent(
                kind: value < 0 ? negativeKind : positiveKind,
                timestamp: timestamp,
                intensity: abs(value)
            )

        case .waitingForNeutral(let since):
            guard abs(value) <= neutralThreshold else {
                state = .waitingForNeutral(since: nil)
                return nil
            }
            if let since, timestamp - since >= neutralHold {
                state = .armed
            } else if since == nil {
                state = .waitingForNeutral(since: timestamp)
            }
            return nil
        }
    }

    mutating func reset() {
        state = .armed
    }
}

private struct PositiveNeutralRecognizer {
    private enum State {
        case armed
        case waitingForNeutral(since: TimeInterval?)
    }

    let activationThreshold: Double
    let neutralThreshold: Double
    let neutralHold: TimeInterval
    let kind: PoseGestureKind
    private var state: State = .armed

    init(
        activationThreshold: Double,
        neutralThreshold: Double,
        neutralHold: TimeInterval,
        kind: PoseGestureKind
    ) {
        self.activationThreshold = activationThreshold
        self.neutralThreshold = neutralThreshold
        self.neutralHold = neutralHold
        self.kind = kind
    }

    mutating func update(
        value: Double,
        timestamp: TimeInterval,
        allowTrigger: Bool
    ) -> PoseGestureEvent? {
        switch state {
        case .armed:
            guard allowTrigger, value >= activationThreshold else { return nil }
            state = .waitingForNeutral(since: nil)
            return PoseGestureEvent(kind: kind, timestamp: timestamp, intensity: value)

        case .waitingForNeutral(let since):
            guard abs(value) <= neutralThreshold else {
                state = .waitingForNeutral(since: nil)
                return nil
            }
            if let since, timestamp - since >= neutralHold {
                state = .armed
            } else if since == nil {
                state = .waitingForNeutral(since: timestamp)
            }
            return nil
        }
    }

    mutating func reset() {
        state = .armed
    }
}

private func degreesToRadians(_ degrees: Double) -> Double {
    degrees * .pi / 180
}

private func shortestAngle(_ angle: Double) -> Double {
    atan2(sin(angle), cos(angle))
}

private func clamp(_ value: Double) -> Double {
    min(max(value, -1), 1)
}

private func clamp01(_ value: Double) -> Double {
    min(max(value, 0), 1)
}

private func median(_ values: [Double]) -> Double {
    guard !values.isEmpty else { return 0 }
    let sorted = values.sorted()
    let midpoint = sorted.count / 2
    if sorted.count.isMultiple(of: 2) {
        return (sorted[midpoint - 1] + sorted[midpoint]) / 2
    }
    return sorted[midpoint]
}

private func standardDeviation(_ values: [Double]) -> Double {
    guard values.count > 1 else { return 0 }
    let mean = values.reduce(0, +) / Double(values.count)
    let variance = values.reduce(0) { partial, value in
        partial + pow(value - mean, 2)
    } / Double(values.count - 1)
    return sqrt(variance)
}
