import CoreVideo
import ImageIO
import Vision

struct ShoulderPoseEstimate: Sendable {
    var signal: Double
    var confidence: Double
    var timestamp: TimeInterval
}

/// Runs infrequently beside face tracking. It deliberately emits only a scalar proxy;
/// recognized body points and pixel buffers are discarded immediately after each request.
enum VisionShoulderEstimator {
    static func estimate(
        pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation,
        timestamp: TimeInterval
    ) -> ShoulderPoseEstimate? {
        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: orientation,
            options: [:]
        )
        do {
            try handler.perform([request])
            return estimate(from: request.results?.first, timestamp: timestamp)
        } catch {
            return nil
        }
    }

    static func estimate(
        from observation: VNHumanBodyPoseObservation?,
        timestamp: TimeInterval
    ) -> ShoulderPoseEstimate? {
        guard let observation,
              let left = try? observation.recognizedPoint(.leftShoulder),
              let right = try? observation.recognizedPoint(.rightShoulder),
              let neck = try? observation.recognizedPoint(.neck) else {
            return nil
        }

        let confidence = Double(min(left.confidence, right.confidence, neck.confidence))
        guard confidence >= 0.2 else { return nil }

        let shoulderWidth = abs(Double(right.location.x - left.location.x))
        guard shoulderWidth >= 0.055 else { return nil }

        let shoulderMidpointY = Double(left.location.y + right.location.y) / 2
        let neckToShoulderDrop = Double(neck.location.y) - shoulderMidpointY

        // The dominant term captures shoulders settling relative to the neck. A smaller
        // width term helps detect a gentle down/back set, but is intentionally conservative.
        let signal = neckToShoulderDrop / shoulderWidth + shoulderWidth * 0.55
        return ShoulderPoseEstimate(
            signal: signal,
            confidence: confidence,
            timestamp: timestamp
        )
    }
}
