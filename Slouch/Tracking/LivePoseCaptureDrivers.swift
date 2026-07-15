import ARKit
import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import ImageIO
import Vision

enum PoseCaptureDriverState: Sendable {
    case running
    case limited(String)
    case interrupted
    case failed(String)
}

protocol PoseCaptureDriver: AnyObject {
    var onMeasurement: ((RawPoseMeasurement) -> Void)? { get set }
    var onStateChange: ((PoseCaptureDriverState) -> Void)? { get set }

    func start() throws
    func stop()
}

enum PoseCaptureDriverError: LocalizedError {
    case trueDepthUnavailable
    case frontCameraUnavailable
    case cameraInputUnavailable
    case cameraOutputUnavailable

    var errorDescription: String? {
        switch self {
        case .trueDepthUnavailable: "TrueDepth face tracking is not available on this device."
        case .frontCameraUnavailable: "A front-facing camera could not be found."
        case .cameraInputUnavailable: "Slouch could not open the front camera input."
        case .cameraOutputUnavailable: "Slouch could not configure private camera processing."
        }
    }
}

/// Preferred driver: ARKit provides stable 3D orientation and translation from TrueDepth.
final class ARKitFaceTrackingDriver: NSObject, PoseCaptureDriver, ARSessionDelegate {
    var onMeasurement: ((RawPoseMeasurement) -> Void)?
    var onStateChange: ((PoseCaptureDriverState) -> Void)?

    private let session = ARSession()
    private let delegateQueue = DispatchQueue(label: "com.slouch.tracking.arkit", qos: .userInteractive)
    private let bodyQueue = DispatchQueue(label: "com.slouch.tracking.arkit.body", qos: .utility)
    private let stateLock = NSLock()
    private let bodyPoseInterval: TimeInterval
    private var latestShoulder: ShoulderPoseEstimate?
    private var nextBodyPoseTimestamp: TimeInterval = 0
    private var isBodyPoseInFlight = false

    init(bodyPoseInterval: TimeInterval) {
        self.bodyPoseInterval = bodyPoseInterval
        super.init()
        session.delegate = self
        session.delegateQueue = delegateQueue
    }

    func start() throws {
        guard ARFaceTrackingConfiguration.isSupported else {
            throw PoseCaptureDriverError.trueDepthUnavailable
        }

        let configuration = ARFaceTrackingConfiguration()
        configuration.isLightEstimationEnabled = false
        configuration.maximumNumberOfTrackedFaces = 1
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }

    func stop() {
        session.pause()
        stateLock.withLock {
            latestShoulder = nil
            nextBodyPoseTimestamp = 0
            isBodyPoseInFlight = false
        }
    }

    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        guard let face = anchors.compactMap({ $0 as? ARFaceAnchor }).first,
              face.isTracked else {
            return
        }

        let timestamp = ProcessInfo.processInfo.systemUptime
        let euler = Self.eulerAngles(from: face.transform)
        let translation = face.transform.columns.3
        let shoulder = currentShoulder(at: timestamp)

        // AR camera coordinates place objects in front of the camera on negative z.
        // Dividing by 3 cm makes a gentle backward translation approximately one unit.
        let depthSignal = Double(-translation.z) / 0.03
        onMeasurement?(
            RawPoseMeasurement(
                timestamp: timestamp,
                yawRadians: euler.yaw,
                pitchRadians: euler.pitch,
                rollRadians: euler.roll,
                depthSignal: depthSignal,
                shoulderSignal: shoulder?.signal,
                faceConfidence: 0.98,
                shoulderConfidence: shoulder?.confidence ?? 0,
                source: .arKitTrueDepth
            )
        )
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let uptime = ProcessInfo.processInfo.systemUptime
        let shouldSchedule = stateLock.withLock { () -> Bool in
            guard uptime >= nextBodyPoseTimestamp, !isBodyPoseInFlight else { return false }
            nextBodyPoseTimestamp = uptime + bodyPoseInterval
            isBodyPoseInFlight = true
            return true
        }
        guard shouldSchedule else { return }

        let pixelBuffer = frame.capturedImage
        bodyQueue.async { [weak self] in
            guard let self else { return }
            let estimate = VisionShoulderEstimator.estimate(
                pixelBuffer: pixelBuffer,
                orientation: .leftMirrored,
                timestamp: uptime
            )
            self.stateLock.withLock {
                if let estimate { self.latestShoulder = estimate }
                self.isBodyPoseInFlight = false
            }
        }
    }

    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        switch camera.trackingState {
        case .normal:
            onStateChange?(.running)
        case .notAvailable:
            onStateChange?(.limited("Face tracking is temporarily unavailable."))
        case .limited(let reason):
            let message: String
            switch reason {
            case .initializing: message = "Preparing face tracking…"
            case .excessiveMotion: message = "Move the phone gently and keep it still."
            case .insufficientFeatures: message = "Use softer, even light on your face."
            case .relocalizing: message = "Reacquiring your neutral position…"
            @unknown default: message = "Face tracking is temporarily limited."
            }
            onStateChange?(.limited(message))
        }
    }

    func sessionWasInterrupted(_ session: ARSession) {
        onStateChange?(.interrupted)
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        if let configuration = session.configuration {
            session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        }
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        onStateChange?(.failed(error.localizedDescription))
    }

    private func currentShoulder(at timestamp: TimeInterval) -> ShoulderPoseEstimate? {
        stateLock.withLock {
            guard let latestShoulder, timestamp - latestShoulder.timestamp <= 1 else { return nil }
            var decayed = latestShoulder
            decayed.confidence *= max(0, 1 - (timestamp - latestShoulder.timestamp) / 1.2)
            return decayed
        }
    }

    private static func eulerAngles(
        from transform: simd_float4x4
    ) -> (pitch: Double, yaw: Double, roll: Double) {
        let quaternion = simd_quatf(transform).vector
        let x = Double(quaternion.x)
        let y = Double(quaternion.y)
        let z = Double(quaternion.z)
        let w = Double(quaternion.w)

        let pitch = atan2(2 * (w * x + y * z), 1 - 2 * (x * x + y * y))
        let yawInput = max(-1, min(1, 2 * (w * y - z * x)))
        let yaw = asin(yawInput)
        let roll = atan2(2 * (w * z + x * y), 1 - 2 * (y * y + z * z))
        return (pitch, yaw, roll)
    }
}

/// Fallback driver for devices without ARKit face tracking. Frames are processed in
/// memory by Vision and are never attached to a preview layer, writer, or photo output.
final class VisionFaceTrackingDriver: NSObject, PoseCaptureDriver, AVCaptureVideoDataOutputSampleBufferDelegate {
    var onMeasurement: ((RawPoseMeasurement) -> Void)?
    var onStateChange: ((PoseCaptureDriverState) -> Void)?

    private let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "com.slouch.tracking.capture.session", qos: .userInitiated)
    private let visionQueue = DispatchQueue(label: "com.slouch.tracking.capture.vision", qos: .userInteractive)
    private let sequenceHandler = VNSequenceRequestHandler()
    private let bodyPoseInterval: TimeInterval
    private var latestShoulder: ShoulderPoseEstimate?
    private var nextBodyPoseTimestamp: TimeInterval = 0
    private var observers: [NSObjectProtocol] = []
    private var isConfigured = false

    init(bodyPoseInterval: TimeInterval) {
        self.bodyPoseInterval = bodyPoseInterval
        super.init()
    }

    func start() throws {
        if !isConfigured {
            try configureSession()
            isConfigured = true
        }
        videoOutput.setSampleBufferDelegate(self, queue: visionQueue)
        installSessionObservers()
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.startRunning()
            self.onStateChange?(.running)
        }
    }

    func stop() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        videoOutput.setSampleBufferDelegate(nil, queue: nil)
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
        visionQueue.async { [weak self] in
            self?.latestShoulder = nil
            self?.nextBodyPoseTimestamp = 0
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard output === videoOutput,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        let timestamp = ProcessInfo.processInfo.systemUptime
        let faceRequest = VNDetectFaceRectanglesRequest()
        faceRequest.revision = VNDetectFaceRectanglesRequestRevision3
        var requests: [VNRequest] = [faceRequest]
        let shouldRunBody = timestamp >= nextBodyPoseTimestamp
        let bodyRequest: VNDetectHumanBodyPoseRequest?
        if shouldRunBody {
            let request = VNDetectHumanBodyPoseRequest()
            bodyRequest = request
            requests.append(request)
            nextBodyPoseTimestamp = timestamp + bodyPoseInterval
        } else {
            bodyRequest = nil
        }

        do {
            try sequenceHandler.perform(
                requests,
                on: pixelBuffer,
                orientation: .leftMirrored
            )
        } catch {
            onStateChange?(.limited("Camera pose processing is recovering…"))
            return
        }

        if let bodyRequest {
            latestShoulder = VisionShoulderEstimator.estimate(
                from: bodyRequest.results?.first,
                timestamp: timestamp
            ) ?? latestShoulder
        }

        guard let face = faceRequest.results?.max(by: {
            $0.confidence == $1.confidence
                ? $0.boundingBox.width < $1.boundingBox.width
                : $0.confidence < $1.confidence
        }) else {
            return
        }

        let faceWidth = max(Double(face.boundingBox.width), 0.05)
        // A roughly 11% reduction in apparent face width maps to one retraction unit.
        let depthSignal = -log(faceWidth) / 0.105
        let shoulder = currentShoulder(at: timestamp)

        onMeasurement?(
            RawPoseMeasurement(
                timestamp: timestamp,
                // Vision is fed a mirrored front-camera orientation. These signs align the
                // resulting axes with the game convention documented on PoseSample.
                yawRadians: -(face.yaw?.doubleValue ?? 0),
                pitchRadians: face.pitch?.doubleValue ?? 0,
                rollRadians: -(face.roll?.doubleValue ?? 0),
                depthSignal: depthSignal,
                shoulderSignal: shoulder?.signal,
                faceConfidence: Double(face.confidence),
                shoulderConfidence: shoulder?.confidence ?? 0,
                source: .visionFrontCamera
            )
        )
    }

    private func configureSession() throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .vga640x480

        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .builtInTrueDepthCamera],
            mediaType: .video,
            position: .front
        )
        guard let camera = discovery.devices.first else {
            throw PoseCaptureDriverError.frontCameraUnavailable
        }
        let input = try AVCaptureDeviceInput(device: camera)
        guard session.canAddInput(input) else {
            throw PoseCaptureDriverError.cameraInputUnavailable
        }
        session.addInput(input)

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]
        guard session.canAddOutput(videoOutput) else {
            throw PoseCaptureDriverError.cameraOutputUnavailable
        }
        session.addOutput(videoOutput)
        videoOutput.setSampleBufferDelegate(self, queue: visionQueue)
    }

    private func installSessionObservers() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = [
            NotificationCenter.default.addObserver(
                forName: .AVCaptureSessionWasInterrupted,
                object: session,
                queue: nil
            ) { [weak self] _ in
                self?.onStateChange?(.interrupted)
            },
            NotificationCenter.default.addObserver(
                forName: .AVCaptureSessionInterruptionEnded,
                object: session,
                queue: nil
            ) { [weak self] _ in
                self?.onStateChange?(.running)
            },
            NotificationCenter.default.addObserver(
                forName: .AVCaptureSessionRuntimeError,
                object: session,
                queue: nil
            ) { [weak self] notification in
                let error = notification.userInfo?[AVCaptureSessionErrorKey] as? Error
                self?.onStateChange?(.failed(error?.localizedDescription ?? "Camera tracking stopped."))
            }
        ]
    }

    private func currentShoulder(at timestamp: TimeInterval) -> ShoulderPoseEstimate? {
        guard let latestShoulder, timestamp - latestShoulder.timestamp <= 1 else { return nil }
        var decayed = latestShoulder
        decayed.confidence *= max(0, 1 - (timestamp - latestShoulder.timestamp) / 1.2)
        return decayed
    }
}

private extension NSLock {
    func withLock<T>(_ work: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try work()
    }
}
