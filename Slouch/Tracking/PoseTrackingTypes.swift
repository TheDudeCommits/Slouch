import Foundation

/// The sensor path currently supplying pose measurements.
enum PoseTrackingSource: String, Codable, CaseIterable, Sendable {
    /// ARKit's TrueDepth face anchor. This is the preferred path on supported iPhones.
    case arKitTrueDepth
    /// Vision face pose over a private AVCaptureSession.
    case visionFrontCamera
    /// Deterministic values supplied by previews, UI tests, or Simulator touch controls.
    case synthetic

    var displayName: String {
        switch self {
        case .arKitTrueDepth: "TrueDepth"
        case .visionFrontCamera: "Front Camera"
        case .synthetic: "Simulator Controls"
        }
    }
}

/// A game-ready pose sample. All movement channels are normalized to `-1 ... 1`.
///
/// Positive yaw means steer right, positive pitch means chin down, and positive roll
/// means bend right. Retraction is positive when the head translates backward from
/// neutral. `shoulderSet` is a conservative 2D proxy and should be presented as a cue,
/// never as a posture diagnosis.
struct PoseSample: Equatable, Sendable {
    var timestamp: TimeInterval
    var yaw: Double
    var pitch: Double
    var roll: Double
    var retraction: Double
    var shoulderSet: Double
    var confidence: Double
    var neutralAlignment: Double
    var motionSmoothness: Double
    var source: PoseTrackingSource
    var isAbruptMotion: Bool
    var controlsAreSafe: Bool

    static let neutral = PoseSample(
        timestamp: 0,
        yaw: 0,
        pitch: 0,
        roll: 0,
        retraction: 0,
        shoulderSet: 0,
        confidence: 0,
        neutralAlignment: 1,
        motionSmoothness: 1,
        source: .synthetic,
        isAbruptMotion: false,
        controlsAreSafe: false
    )

    var hasReliableFace: Bool {
        confidence >= 0.55
    }
}

/// Raw neutral measurements captured during the setup hold.
struct PoseBaseline: Codable, Equatable, Sendable {
    var yawRadians: Double
    var pitchRadians: Double
    var rollRadians: Double
    var depthSignal: Double
    var shoulderSignal: Double?
    var source: PoseTrackingSource
    var capturedAt: Date
    var sampleCount: Int

    static let syntheticNeutral = PoseBaseline(
        yawRadians: 0,
        pitchRadians: 0,
        rollRadians: 0,
        depthSignal: 0,
        shoulderSignal: 0,
        source: .synthetic,
        capturedAt: .now,
        sampleCount: 1
    )
}

enum PoseCalibrationFailure: String, Codable, Equatable, Sendable {
    case faceNotVisible
    case lowConfidence
    case movementTooLarge
    case trackingInterrupted

    var message: String {
        switch self {
        case .faceNotVisible: "Keep your face and upper shoulders in view."
        case .lowConfidence: "Move to softer, even lighting and try again."
        case .movementTooLarge: "Hold a comfortable neutral position for a moment."
        case .trackingInterrupted: "Camera tracking was interrupted. Please try again."
        }
    }
}

enum PoseCalibrationState: Equatable, Sendable {
    case notCalibrated
    case collecting(progress: Double, acceptedSamples: Int)
    case calibrated(PoseBaseline)
    case failed(PoseCalibrationFailure)

    var isCalibrated: Bool {
        if case .calibrated = self { true } else { false }
    }
}

enum CameraAccessState: String, Codable, Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
    case restricted
    case unavailable
}

enum PoseTrackingStatus: Equatable, Sendable {
    case idle
    case requestingPermission
    case starting(PoseTrackingSource)
    case tracking(PoseTrackingSource)
    case trackingLimited(reason: String)
    case trackingLost
    case pausedForAbruptMotion
    case interrupted
    case permissionDenied
    case unavailable(reason: String)
    case failed(message: String)

    var isReceivingPose: Bool {
        switch self {
        case .tracking, .pausedForAbruptMotion: true
        default: false
        }
    }

    var source: PoseTrackingSource? {
        switch self {
        case .starting(let source), .tracking(let source): source
        default: nil
        }
    }
}

enum PoseGestureKind: String, Codable, CaseIterable, Sendable {
    case nodDown
    case nodUp
    case retraction
    case sideBendLeft
    case sideBendRight
    case shoulderSet
}

/// A discrete action fires only once, then requires a stable return to neutral before rearming.
struct PoseGestureEvent: Identifiable, Equatable, Sendable {
    let id: UUID
    let kind: PoseGestureKind
    let timestamp: TimeInterval
    let intensity: Double

    init(
        id: UUID = UUID(),
        kind: PoseGestureKind,
        timestamp: TimeInterval,
        intensity: Double
    ) {
        self.id = id
        self.kind = kind
        self.timestamp = timestamp
        self.intensity = max(0, min(intensity, 1))
    }
}

struct AbruptMotionEvent: Identifiable, Equatable, Sendable {
    let id: UUID
    let timestamp: TimeInterval
    /// Highest observed angular velocity, in degrees per second.
    let angularVelocity: Double

    init(id: UUID = UUID(), timestamp: TimeInterval, angularVelocity: Double) {
        self.id = id
        self.timestamp = timestamp
        self.angularVelocity = angularVelocity
    }
}

/// Tunable software thresholds. These are interaction settings, not medical targets.
struct PoseTrackingConfiguration: Equatable, Sendable {
    var sensitivity: Double
    var yawRangeDegrees: Double
    var pitchRangeDegrees: Double
    var rollRangeDegrees: Double
    var shoulderRange: Double
    var minimumConfidence: Double
    var calibrationDuration: TimeInterval
    var calibrationTimeout: TimeInterval
    var trackingLossDelay: TimeInterval
    var abruptAngularVelocityDegreesPerSecond: Double
    var abruptDepthVelocity: Double
    var abruptMotionPause: TimeInterval
    var bodyPoseInterval: TimeInterval

    static let `default` = PoseTrackingConfiguration(
        sensitivity: 1,
        yawRangeDegrees: 14,
        pitchRangeDegrees: 10,
        rollRangeDegrees: 10,
        shoulderRange: 0.18,
        minimumConfidence: 0.55,
        calibrationDuration: 1.25,
        calibrationTimeout: 4,
        trackingLossDelay: 0.7,
        abruptAngularVelocityDegreesPerSecond: 115,
        abruptDepthVelocity: 4.5,
        abruptMotionPause: 0.75,
        bodyPoseInterval: 0.3
    )

    mutating func sanitize() {
        sensitivity = sensitivity.clamped(to: 0.5 ... 1.75)
        yawRangeDegrees = yawRangeDegrees.clamped(to: 8 ... 24)
        pitchRangeDegrees = pitchRangeDegrees.clamped(to: 6 ... 18)
        rollRangeDegrees = rollRangeDegrees.clamped(to: 6 ... 18)
        shoulderRange = shoulderRange.clamped(to: 0.08 ... 0.4)
        minimumConfidence = minimumConfidence.clamped(to: 0.3 ... 0.95)
        calibrationDuration = calibrationDuration.clamped(to: 0.8 ... 3)
        calibrationTimeout = max(calibrationDuration + 0.5, calibrationTimeout)
        trackingLossDelay = trackingLossDelay.clamped(to: 0.35 ... 2)
        abruptAngularVelocityDegreesPerSecond = abruptAngularVelocityDegreesPerSecond.clamped(to: 60 ... 220)
        abruptDepthVelocity = abruptDepthVelocity.clamped(to: 2 ... 10)
        abruptMotionPause = abruptMotionPause.clamped(to: 0.4 ... 2)
        bodyPoseInterval = bodyPoseInterval.clamped(to: 0.18 ... 1)
    }
}

/// Explicit privacy properties that setup/about UI can display without duplicating copy.
enum PoseTrackingPrivacy {
    static let processing = "All camera processing happens on this iPhone."
    static let retention = "Slouch does not record, save, or upload camera frames."
    static let storedData = "Only anonymous movement measurements and run metrics may be saved."
}

extension Double {
    fileprivate func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
