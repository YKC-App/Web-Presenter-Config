//
//  PTZController.swift
//  NDIMonitor
//
//  Deliverable #4 (PTZ). Translates joystick/slider/button intents into
//  `PTZCommand`s and sends them through the source's receiver over the NDI PTZ
//  control protocol. Also tracks last-known PTZ state and named presets.
//
//  Pan/tilt uses a configurable easing curve: the *applied* velocity eases
//  toward the *target* velocity each tick, so the camera accelerates and
//  decelerates smoothly on stick engage/release (and for auto-tracking).
//
//  IMPORTANT: opening a control panel must never move the camera. Nothing in
//  this controller sends a command on init — commands are only sent in response
//  to explicit user/auto-tracking actions.
//

import Combine
import Foundation

@MainActor
final class PTZController: ObservableObject {

    // Last-known state (see NDIPTZStatus note: NDI PTZ is write-only).
    @Published var status = NDIPTZStatus()
    @Published var presets: [PTZPreset]

    /// True while a continuous pan/tilt drive is in flight.
    @Published private(set) var isDriving = false

    /// Overall pan/tilt speed multiplier applied to joystick output (0.05…1.0).
    @Published var panTiltSpeed: Float = 0.5 {
        didSet { target = (rawPanTilt.pan * panTiltSpeed, rawPanTilt.tilt * panTiltSpeed) }
    }

    /// Easing strength for pan/tilt, 0 (instant) … 1 (very smooth / long ramp).
    /// Configurable from the UI; drives the per-tick smoothing factor.
    @Published var easing: Float = 0.35

    private let receiver: NDIReceiverHandle
    private var statusTask: Task<Void, Never>?

    // Pan/tilt drive state. The loop runs on the main actor (Task inherits the
    // @MainActor context), so these are safe to touch without extra locking.
    private var driveTask: Task<Void, Never>?
    private var rawPanTilt: (pan: Float, tilt: Float) = (0, 0)   // before speed scaling
    private var target: (pan: Float, tilt: Float) = (0, 0)        // after speed scaling
    private var applied: (pan: Float, tilt: Float) = (0, 0)       // eased, actually sent
    private var released = true

    init(receiver: NDIReceiverHandle, presets: [PTZPreset] = PTZPreset.defaults) {
        self.receiver = receiver
        self.presets = presets
        observeStatus()
    }

    private func observeStatus() {
        statusTask = Task { [weak self] in
            guard let self else { return }
            for await event in receiver.events {
                if case .ptzStatus(let s) = event { self.status = s }
            }
        }
    }

    deinit {
        statusTask?.cancel()
        driveTask?.cancel()
        // Safety: never leave the camera moving when the controller goes away.
        receiver.send(.panTilt(pan: 0, tilt: 0))
        receiver.send(.zoom(speed: 0))
    }

    // MARK: Pan / Tilt (continuous eased drive)

    /// Per-tick smoothing factor in (0,1]. Lower = smoother/slower approach.
    private var easeAlpha: Float {
        // easing 0 → 1.0 (instant), easing 1 → ~0.06 (long, gentle ramp).
        max(0.06, 1.0 - easing * 0.94)
    }

    /// Called continuously while the joystick is held. `pan`/`tilt` are −1…1.
    func drive(pan: Float, tilt: Float) {
        released = false
        rawPanTilt = (pan, tilt)
        target = (pan * panTiltSpeed, tilt * panTiltSpeed)
        startLoopIfNeeded()
    }

    /// Called when the joystick is released — eases the camera to a smooth stop.
    func endDrive() {
        released = true
        rawPanTilt = (0, 0)
        target = (0, 0)
        // The loop eases `applied` to ~0, sends a final stop, then exits.
    }

    private func startLoopIfNeeded() {
        guard driveTask == nil else { return }
        isDriving = true
        driveTask = Task { [weak self] in
            defer {
                self?.applied = (0, 0)
                self?.driveTask = nil
                self?.isDriving = false
            }
            while !Task.isCancelled {
                guard let self else { return }
                let a = self.easeAlpha
                self.applied.pan += (self.target.pan - self.applied.pan) * a
                self.applied.tilt += (self.target.tilt - self.applied.tilt) * a
                self.receiver.send(.panTilt(pan: self.applied.pan, tilt: self.applied.tilt))

                // Exit once released and we've eased essentially to a stop.
                if self.released,
                   abs(self.applied.pan) < 0.01, abs(self.applied.tilt) < 0.01 {
                    self.receiver.send(.panTilt(pan: 0, tilt: 0))
                    return
                }
                try? await Task.sleep(nanoseconds: 50_000_000) // 20 Hz
            }
        }
    }

    // MARK: Zoom / Focus

    func zoom(speed: Float) { receiver.send(.zoom(speed: speed)) }
    func stopZoom() { receiver.send(.zoom(speed: 0)) }
    func setZoom(_ value: Float) { receiver.send(.zoomAbsolute(value)) }

    func focus(speed: Float) { receiver.send(.focus(speed: speed)) }
    func stopFocus() { receiver.send(.focus(speed: 0)) }
    func setAutoFocus(_ on: Bool) {
        status.autoFocus = on
        receiver.send(.autoFocus(on))
    }

    // MARK: Iris / Exposure

    func setIris(_ level: Float) {
        status.iris = level
        status.autoIris = false
        receiver.send(.irisAbsolute(level))
    }
    func setAutoIris(_ on: Bool) {
        status.autoIris = on
        receiver.send(.autoIris(on))
    }

    // MARK: White balance

    func setWhiteBalance(_ mode: WhiteBalanceMode) {
        status.whiteBalance = mode
        if mode == .manual {
            receiver.send(.whiteBalanceManual(red: status.wbRed, blue: status.wbBlue))
        } else {
            receiver.send(.whiteBalance(mode))
        }
    }
    func setWhiteBalanceManual(red: Float, blue: Float) {
        status.whiteBalance = .manual
        status.wbRed = red
        status.wbBlue = blue
        receiver.send(.whiteBalanceManual(red: red, blue: blue))
    }

    // MARK: Presets

    func recall(_ preset: PTZPreset, speed: Float = 0.5) {
        receiver.send(.recallPreset(index: preset.index, speed: speed))
    }

    func store(_ preset: PTZPreset) {
        receiver.send(.storePreset(index: preset.index))
    }

    func rename(_ preset: PTZPreset, to name: String) {
        guard let i = presets.firstIndex(of: preset) else { return }
        presets[i].name = name
    }

    /// Send a raw command (used by the auto-angle controller).
    func send(_ command: PTZCommand) { receiver.send(command) }
}
