//
//  AutoAngleController.swift
//  NDIMonitor
//
//  Deliverable #5: automatic angle control (proof-of-concept). Subscribes to a
//  source's video frames, runs `SubjectTracker` (Vision) to locate the subject,
//  and drives PTZ so the subject stays centred and well-framed.
//
//  Control law: a simple proportional controller on the framing error. The
//  subject's centre offset from the image centre drives pan/tilt velocity; the
//  subject's size relative to a target fill ratio drives zoom. A dead-zone
//  around centre prevents constant micro-corrections (and looks natural on air).
//

import Combine
import CoreGraphics
import CoreVideo
import Foundation

@MainActor
final class AutoAngleController: ObservableObject {

    @Published var isEnabled = false {
        didSet { isEnabled ? start() : stop() }
    }

    /// 0…1: higher = more aggressive corrections.
    @Published var sensitivity: Float = 0.5

    /// Desired fraction of frame height the subject should fill (framing).
    @Published var targetFill: CGFloat = 0.35

    /// Whether to also auto-zoom, or only pan/tilt.
    @Published var autoZoom = true

    /// Latest detections, for UI overlay.
    @Published private(set) var subjects: [TrackedSubject] = []
    @Published private(set) var hasLock = false

    let tracker = SubjectTracker()

    private let receiver: NDIReceiverHandle
    private let ptz: PTZController
    private var task: Task<Void, Never>?

    /// Centre dead-zone (normalised): no correction while error is below this.
    private let deadZone: CGFloat = 0.06
    /// Throttle Vision to keep CPU/thermals in check.
    private var lastAnalysis = Date.distantPast
    private let minInterval: TimeInterval = 1.0 / 10.0  // ~10 Hz analysis

    init(receiver: NDIReceiverHandle, ptz: PTZController) {
        self.receiver = receiver
        self.ptz = ptz
    }

    deinit { task?.cancel() }

    private func start() {
        task = Task { [weak self] in
            guard let self else { return }
            for await event in receiver.events {
                guard case .video(let frame) = event else { continue }
                await self.process(frame.pixelBuffer)
            }
        }
    }

    private func stop() {
        task?.cancel()
        task = nil
        hasLock = false
        subjects = []
        ptz.endDrive()        // release the camera
    }

    private func process(_ pixelBuffer: CVPixelBuffer) async {
        guard Date().timeIntervalSince(lastAnalysis) >= minInterval else { return }
        lastAnalysis = Date()

        // Run Vision off the main actor.
        let detected = await Task.detached(priority: .userInitiated) { [tracker] in
            tracker.detect(in: pixelBuffer)
        }.value

        self.subjects = detected
        guard let target = tracker.target(among: detected) else {
            hasLock = false
            ptz.send(.panTilt(pan: 0, tilt: 0))   // hold position, no subject
            return
        }
        hasLock = true
        applyControl(for: target)
    }

    /// Proportional framing controller → PTZ velocities.
    private func applyControl(for target: TrackedSubject) {
        let box = target.boundingBox  // Vision: origin bottom-left

        // Framing error from image centre (0.5, 0.5), normalised −0.5…0.5.
        let errX = box.midX - 0.5
        // Convert Vision's bottom-left Y to top-left so "up" is positive tilt.
        let errY = (1.0 - box.midY) - 0.5

        let gain = Float(0.5 + Double(sensitivity) * 1.5)   // 0.5…2.0

        let pan = abs(errX) > deadZone ? Float(errX) * gain : 0
        // Tilt sign: subject above centre (errY < 0) → tilt up (positive).
        let tilt = abs(errY) > deadZone ? Float(-errY) * gain : 0

        // Zoom toward the desired fill ratio.
        var zoom: Float = 0
        if autoZoom {
            let fillError = Float(targetFill - box.height)   // >0 → too small → zoom in
            if abs(fillError) > 0.05 { zoom = max(-1, min(1, fillError * gain)) }
        }

        ptz.send(.panTilt(pan: clamp(pan), tilt: clamp(tilt)))
        if autoZoom { ptz.send(.zoom(speed: clamp(zoom))) }
    }

    private func clamp(_ v: Float) -> Float { max(-1, min(1, v)) }
}
