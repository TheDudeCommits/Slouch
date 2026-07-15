import Foundation

/// Normalized input for Simulator, previews, UI tests, and an optional touch fallback.
struct SyntheticPoseInput: Equatable, Sendable {
    var yaw: Double
    var pitch: Double
    var roll: Double
    var retraction: Double
    var shoulderSet: Double
    var confidence: Double

    static let neutral = SyntheticPoseInput(
        yaw: 0,
        pitch: 0,
        roll: 0,
        retraction: 0,
        shoulderSet: 0,
        confidence: 1
    )

    func sanitized() -> SyntheticPoseInput {
        SyntheticPoseInput(
            yaw: Self.clampSigned(yaw),
            pitch: Self.clampSigned(pitch),
            roll: Self.clampSigned(roll),
            retraction: Self.clampSigned(retraction),
            shoulderSet: Self.clampSigned(shoulderSet),
            confidence: min(max(confidence, 0), 1)
        )
    }

    private static func clampSigned(_ value: Double) -> Double {
        min(max(value, -1), 1)
    }
}

/// Selects how a SwiftUI `DragGesture` translation maps into synthetic pose channels.
enum SyntheticTouchMapping: String, CaseIterable, Sendable {
    case steerAndNod
    case sideBend
    case retraction
    case shoulderSet
}
