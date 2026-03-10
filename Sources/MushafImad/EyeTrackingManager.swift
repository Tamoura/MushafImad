//
//  EyeTrackingManager.swift
//  MushafImad
//
//  Manages eye-tracking / gaze estimation using ARKit face tracking
//  to detect which Quranic verse the user is reading.
//
//  Privacy-first: all processing is local, opt-in only, no data leaves the device.
//

import SwiftUI
import Combine

#if canImport(ARKit) && canImport(UIKit)
import ARKit

/// Represents the user's estimated gaze point on the screen.
public struct GazePoint: Equatable, Sendable {
    /// Normalized X coordinate (0 = left, 1 = right)
    public let x: CGFloat
    /// Normalized Y coordinate (0 = top, 1 = bottom)
    public let y: CGFloat
    /// Confidence level of the gaze estimate (0–1)
    public let confidence: CGFloat
    /// Timestamp of this gaze sample
    public let timestamp: TimeInterval

    public static let zero = GazePoint(x: 0.5, y: 0.5, confidence: 0, timestamp: 0)
}

/// Core manager for ARKit-based eye/gaze tracking.
/// Uses the TrueDepth camera to estimate where the user is looking on screen.
@MainActor
public final class EyeTrackingManager: NSObject, ObservableObject {

    // MARK: - Published State

    /// Whether eye tracking is actively running
    @Published public private(set) var isTracking = false

    /// Whether the device supports face tracking
    @Published public private(set) var isSupported = false

    /// Current smoothed gaze point on screen
    @Published public private(set) var currentGaze: GazePoint = .zero

    /// Whether a face is currently detected
    @Published public private(set) var isFaceDetected = false

    /// Whether the user appears to be looking at the screen
    @Published public private(set) var isLookingAtScreen = false

    // MARK: - Settings (AppStorage-backed)

    @AppStorage("eye_tracking_enabled") public var isEnabled: Bool = false {
        didSet { updateTrackingState() }
    }

    @AppStorage("eye_tracking_show_indicator") public var showGazeIndicator: Bool = false
    @AppStorage("eye_tracking_auto_page") public var autoPageEnabled: Bool = false
    @AppStorage("eye_tracking_dwell_seconds") public var dwellTimeSeconds: Double = 3.0
    @AppStorage("eye_tracking_smoothing") public var smoothingFactor: Double = 0.15

    // MARK: - Private

    private var arSession: ARSession?
    private var gazeHistory: [GazePoint] = []
    private let maxGazeHistory = 10
    private var settingsCancellable: AnyCancellable?

    /// Screen dimensions used to map gaze vectors to screen coordinates
    private var screenSize: CGSize = .zero

    /// Calibration offsets (user can fine-tune)
    private var calibrationOffsetX: CGFloat = 0
    private var calibrationOffsetY: CGFloat = 0

    // MARK: - Callbacks

    /// Called when gaze dwells on the bottom portion of the page (potential auto-advance)
    public var onBottomDwell: (() -> Void)?

    /// Called with updated gaze point at each frame
    public var onGazeUpdate: ((GazePoint) -> Void)?

    // MARK: - Init

    public override init() {
        super.init()
        checkSupport()
        settingsCancellable = NotificationCenter.default
            .publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateTrackingState()
            }
    }

    // MARK: - Support Check

    private func checkSupport() {
        isSupported = ARFaceTrackingConfiguration.isSupported
    }

    // MARK: - Lifecycle

    public func activate(screenSize: CGSize) {
        self.screenSize = screenSize
        updateTrackingState()
    }

    public func deactivate() {
        stopTracking()
    }

    private func updateTrackingState() {
        if isEnabled && isSupported && !isTracking {
            startTracking()
        } else if (!isEnabled || !isSupported) && isTracking {
            stopTracking()
        }
    }

    private func startTracking() {
        guard isSupported, !isTracking else { return }

        let configuration = ARFaceTrackingConfiguration()
        configuration.isWorldTrackingEnabled = false

        let session = ARSession()
        session.delegate = self
        session.run(configuration, options: [.resetTracking])

        arSession = session
        isTracking = true
    }

    private func stopTracking() {
        arSession?.pause()
        arSession = nil
        isTracking = false
        isFaceDetected = false
        isLookingAtScreen = false
        currentGaze = .zero
        gazeHistory.removeAll()
    }

    // MARK: - Gaze Estimation

    /// Projects the eye gaze vectors from the face anchor onto a virtual screen plane
    /// to estimate where the user is looking.
    private func estimateGaze(from faceAnchor: ARFaceAnchor, camera: ARCamera) -> GazePoint {
        // Get the face transform in world space
        let faceTransform = faceAnchor.transform

        // Extract left and right eye transforms (relative to face)
        let leftEyeTransform = faceAnchor.leftEyeTransform
        let rightEyeTransform = faceAnchor.rightEyeTransform

        // Compute the average eye gaze direction in face-local space
        let leftEyeForward = simd_float3(
            -leftEyeTransform.columns.2.x,
            -leftEyeTransform.columns.2.y,
            -leftEyeTransform.columns.2.z
        )
        let rightEyeForward = simd_float3(
            -rightEyeTransform.columns.2.x,
            -rightEyeTransform.columns.2.y,
            -rightEyeTransform.columns.2.z
        )

        let avgGazeDirection = simd_normalize((leftEyeForward + rightEyeForward) / 2.0)

        // Average eye position in face space
        let leftEyePosition = simd_float3(
            leftEyeTransform.columns.3.x,
            leftEyeTransform.columns.3.y,
            leftEyeTransform.columns.3.z
        )
        let rightEyePosition = simd_float3(
            rightEyeTransform.columns.3.x,
            rightEyeTransform.columns.3.y,
            rightEyeTransform.columns.3.z
        )
        let avgEyePosition = (leftEyePosition + rightEyePosition) / 2.0

        // Transform eye position to world space
        let eyePositionWorld4 = faceTransform * simd_float4(avgEyePosition, 1.0)
        let eyePositionWorld = simd_float3(eyePositionWorld4.x, eyePositionWorld4.y, eyePositionWorld4.z)

        // Transform gaze direction to world space
        let gazeDirectionWorld4 = faceTransform * simd_float4(avgGazeDirection, 0.0)
        let gazeDirectionWorld = simd_normalize(
            simd_float3(gazeDirectionWorld4.x, gazeDirectionWorld4.y, gazeDirectionWorld4.z)
        )

        // Project the gaze ray onto the camera's near plane to get screen coordinates.
        // The camera looks along its -Z axis in world space.
        let cameraTransform = camera.transform
        let cameraPosition = simd_float3(
            cameraTransform.columns.3.x,
            cameraTransform.columns.3.y,
            cameraTransform.columns.3.z
        )

        // Use the camera's projection matrix to estimate screen-space position
        let viewMatrix = camera.viewMatrix(for: .portrait)
        let projectionMatrix = camera.projectionMatrix(for: .portrait,
                                                       viewportSize: screenSize,
                                                       zNear: 0.001,
                                                       zFar: 1000)

        // Project a point along the gaze ray onto screen
        let gazeTarget = eyePositionWorld + gazeDirectionWorld * 0.5
        let gazeTarget4 = simd_float4(gazeTarget, 1.0)

        let viewProjection = projectionMatrix * viewMatrix
        let clipSpace = viewProjection * gazeTarget4

        guard clipSpace.w != 0 else {
            return GazePoint(x: 0.5, y: 0.5, confidence: 0, timestamp: CACurrentMediaTime())
        }

        // Normalized device coordinates
        let ndcX = clipSpace.x / clipSpace.w
        let ndcY = clipSpace.y / clipSpace.w

        // Convert from NDC [-1, 1] to screen [0, 1]
        var screenX = CGFloat((ndcX + 1.0) / 2.0) + calibrationOffsetX
        var screenY = CGFloat((1.0 - ndcY) / 2.0) + calibrationOffsetY

        // Clamp to valid range
        screenX = max(0, min(1, screenX))
        screenY = max(0, min(1, screenY))

        // Compute confidence based on:
        // 1. How close the gaze is to looking at the screen
        // 2. Blend shape values for eye openness
        let lookAtDeviation = simd_distance(cameraPosition, gazeTarget)
        let eyeBlinkLeft = faceAnchor.blendShapes[.eyeBlinkLeft]?.floatValue ?? 0
        let eyeBlinkRight = faceAnchor.blendShapes[.eyeBlinkRight]?.floatValue ?? 0
        let avgBlink = (eyeBlinkLeft + eyeBlinkRight) / 2.0

        // Eyes open and looking forward = high confidence
        var confidence = CGFloat(max(0, 1.0 - avgBlink)) * CGFloat(max(0, 1.0 - lookAtDeviation * 2))
        confidence = max(0, min(1, confidence))

        return GazePoint(
            x: screenX,
            y: screenY,
            confidence: confidence,
            timestamp: CACurrentMediaTime()
        )
    }

    /// Applies exponential smoothing to reduce jitter in gaze estimation.
    private func smoothGaze(_ newPoint: GazePoint) -> GazePoint {
        let alpha = CGFloat(smoothingFactor)

        gazeHistory.append(newPoint)
        if gazeHistory.count > maxGazeHistory {
            gazeHistory.removeFirst()
        }

        let smoothedX = currentGaze.x * (1 - alpha) + newPoint.x * alpha
        let smoothedY = currentGaze.y * (1 - alpha) + newPoint.y * alpha

        // Average confidence over recent samples
        let avgConfidence = gazeHistory.reduce(CGFloat(0)) { $0 + $1.confidence }
            / CGFloat(gazeHistory.count)

        return GazePoint(
            x: smoothedX,
            y: smoothedY,
            confidence: avgConfidence,
            timestamp: newPoint.timestamp
        )
    }
}

// MARK: - ARSessionDelegate

extension EyeTrackingManager: @preconcurrency ARSessionDelegate {

    nonisolated public func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        guard let faceAnchor = anchors.compactMap({ $0 as? ARFaceAnchor }).first,
              let frame = session.currentFrame else { return }

        let camera = frame.camera
        let rawGaze = MainActor.assumeIsolated {
            estimateGaze(from: faceAnchor, camera: camera)
        }

        MainActor.assumeIsolated {
            let eyeBlinkLeft = faceAnchor.blendShapes[.eyeBlinkLeft]?.floatValue ?? 0
            let eyeBlinkRight = faceAnchor.blendShapes[.eyeBlinkRight]?.floatValue ?? 0
            let avgBlink = (eyeBlinkLeft + eyeBlinkRight) / 2.0

            isFaceDetected = true
            isLookingAtScreen = rawGaze.confidence > 0.3 && avgBlink < 0.5

            if isLookingAtScreen {
                let smoothed = smoothGaze(rawGaze)
                currentGaze = smoothed
                onGazeUpdate?(smoothed)
            }
        }
    }

    nonisolated public func session(_ session: ARSession, didFailWithError error: Error) {
        MainActor.assumeIsolated {
            isTracking = false
            isFaceDetected = false
        }
    }
}
#else

// MARK: - Stub for non-ARKit platforms (macOS)

public struct GazePoint: Equatable, Sendable {
    public let x: CGFloat
    public let y: CGFloat
    public let confidence: CGFloat
    public let timestamp: TimeInterval
    public static let zero = GazePoint(x: 0.5, y: 0.5, confidence: 0, timestamp: 0)
}

@MainActor
public final class EyeTrackingManager: ObservableObject {
    @Published public private(set) var isTracking = false
    @Published public private(set) var isSupported = false
    @Published public private(set) var currentGaze: GazePoint = .zero
    @Published public private(set) var isFaceDetected = false
    @Published public private(set) var isLookingAtScreen = false

    @AppStorage("eye_tracking_enabled") public var isEnabled: Bool = false
    @AppStorage("eye_tracking_show_indicator") public var showGazeIndicator: Bool = false
    @AppStorage("eye_tracking_auto_page") public var autoPageEnabled: Bool = false
    @AppStorage("eye_tracking_dwell_seconds") public var dwellTimeSeconds: Double = 3.0
    @AppStorage("eye_tracking_smoothing") public var smoothingFactor: Double = 0.15

    public var onBottomDwell: (() -> Void)?
    public var onGazeUpdate: ((GazePoint) -> Void)?

    public init() {}
    public func activate(screenSize: CGSize) {}
    public func deactivate() {}
}
#endif
