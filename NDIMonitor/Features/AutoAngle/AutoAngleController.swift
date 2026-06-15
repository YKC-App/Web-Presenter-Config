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

    /// Observable mirror of the tracker's mode so SwiftUI pickers update.
    @Published var trackingMode: TrackingMode = .face {
        didSet { tracker.mode = trackingMode }
    }

    /// Latest detections, for UI overlay.
    @Published private(set) var subjects: [TrackedSubject] = []
    @Published private(set) var hasLock = false

    /// Current target box in **top-left** normalised coords (0…1) for the UI
    /// overlay, or nil when there is no lock.
    @Published private(set) var targetBoxTopLeft: CGRect?

    let tracker = SubjectTracker()

    private let receiver: NDIReceiverHandle
    private let ptz: PTZController
    private var task: Task<Void, Never>?

    /// Centre dead-zone (normalised): no correction while error is below this.
    private let deadZone: CGFloat = 0.06
    /// Throttle Vision to keep CPU/thermals in check.
    private var lastAnalysis = Date.distantPast
    private let minInterval: TimeInterval = 1.0 / 10.0  // ~10 Hz analysis

    /// When tracking, re-assert auto-focus on this cadence so the camera keeps
    /// focus locked on the moving subject.
    private var lastAFAssert = Date.distantPast
    private let afAssertInterval: TimeInterval = 3.0

    init(receiver: NDIReceiverHandle, ptz: PTZController) {
        self.receiver = receiver
        self.ptz = ptz
    }

    deinit { task?.cancel() }

    private func start() {
        // Force auto-focus on while tracking (spec: 追尾中は強制的にAF).
        ptz.setAutoFocus(true)
        lastAFAssert = Date()
        task = Task { [weak self] in
            guard let self else { return }
            for await event in receiver.events {
                if Task.isCancelled { break }
                if !self.isEnabled { break }
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
        targetBoxTopLeft = nil
        ptz.endDrive()        // smooth eased release of pan/tilt
        ptz.stopZoom()        // halt any in-progress auto-zoom
    }

    /// Seed manual-region tracking from a top-left normalised rect drawn on the
    /// preview, and switch the tracker into region mode.
    func setManualRegion(topLeftRect rect: CGRect) {
        trackingMode = .manualRegion          // keeps the picker in sync
        tracker.beginManualRegion(topLeftRect: rect)
    }

    private func process(_ pixelBuffer: CVPixelBuffer) async {
        guard isEnabled else { return }
        guard Date().timeIntervalSince(lastAnalysis) >= minInterval else { return }
        lastAnalysis = Date()

        // Re-assert auto-focus periodically so it stays on through zoom/pan.
        if Date().timeIntervalSince(lastAFAssert) >= afAssertInterval {
            ptz.setAutoFocus(true)
            lastAFAssert = Date()
        }

        // Run Vision off the main actor.
        let detected = await Task.detached(priority: .userInitiated) { [tracker] in
            tracker.detect(in: pixelBuffer)
        }.value

        // Tracking may have been switched off while Vision was running — if so,
        // release the camera and do NOT issue any further drive (this is what
        // makes turning Auto Tracking off actually return control to manual).
        guard isEnabled else {
            ptz.endDrive()
            ptz.stopZoom()
            return
        }

        self.subjects = detected
        guard let target = tracker.target(among: detected) else {
            hasLock = false
            targetBoxTopLeft = nil
            ptz.endDrive()        // no subject → eased stop (no hard halt)
            ptz.stopZoom()
            return
        }
        hasLock = true
        // Publish the box in top-left coords for the overlay.
        let b = target.boundingBox
        targetBoxTopLeft = CGRect(x: b.minX, y: 1.0 - b.maxY, width: b.width, height: b.height)
        applyControl(for: target)
    }

    /// Proportional framing controller → eased PTZ drive (smooth accel/decel).
    private func applyControl(for target: TrackedSubject) {
        let box = target.boundingBox  // Vision: origin bottom-left

        // Framing error from image centre (0.5, 0.5), normalised −0.5…0.5.
        let errX = box.midX - 0.5
        // Convert Vision's bottom-left Y to top-left so "up" is positive tilt.
        let errY = (1.0 - box.midY) - 0.5

        let gain = Float(0.5 + Double(sensitivity) * 1.5)   // 0.5…2.0

        // Pan sign matches the joystick convention (negative pan = camera right).
        // Subject right of centre (errX > 0) → pan the camera right to recentre.
        let pan = abs(errX) > deadZone ? Float(-errX) * gain : 0
        // Tilt: subject above centre (errY < 0) → tilt up (positive) to recentre.
        let tilt = abs(errY) > deadZone ? Float(-errY) * gain : 0

        // Route through PTZController.drive so the configured easing curve gives
        // smooth start/stop (spec: 動き出し・停止時は緩和曲線).
        ptz.drive(pan: clamp(pan), tilt: clamp(tilt))

        // Zoom toward the desired fill ratio.
        if autoZoom {
            let fillError = Float(targetFill - box.height)   // >0 → too small → zoom in
            let zoom = abs(fillError) > 0.05 ? clamp(fillError * gain) : 0
            ptz.send(.zoom(speed: zoom))
        }
    }

    private func clamp(_ v: Float) -> Float { max(-1, min(1, v)) }
}
