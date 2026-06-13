//
//  PTZController.swift
//  NDIMonitor
//
//  Deliverable #4 (PTZ). Translates joystick/slider/button intents into
//  `PTZCommand`s and sends them through the source's receiver over the NDI PTZ
//  control protocol. Also tracks live PTZ status and named presets.
//

import Combine
import Foundation

@MainActor
final class PTZController: ObservableObject {

    @Published var status = NDIPTZStatus()
    @Published var presets: [PTZPreset]
    /// True while a continuous pan/tilt drive is in flight.
    @Published private(set) var isDriving = false

    private let receiver: NDIReceiverHandle
    private var statusTask: Task<Void, Never>?

    /// Throttle continuous pan/tilt so we don't flood the camera; NDI cameras
    /// expect a steady command rate (~20 Hz) while a stick is held.
    private var driveTask: Task<Void, Never>?
    private var currentPanTilt: (pan: Float, tilt: Float) = (0, 0)

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

    deinit { statusTask?.cancel(); driveTask?.cancel() }

    // MARK: Pan / Tilt (continuous drive from the joystick)

    /// Called continuously while the joystick is held. `pan`/`tilt` are −1…1.
    /// A steady ~20 Hz repeater re-sends the latest stick vector so the camera
    /// keeps moving smoothly without us flooding it on every touch event.
    func drive(pan: Float, tilt: Float) {
        currentPanTilt = (pan, tilt)
        guard driveTask == nil else { return }
        isDriving = true
        driveTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.receiver.send(.panTilt(pan: self.currentPanTilt.pan,
                                            tilt: self.currentPanTilt.tilt))
                try? await Task.sleep(nanoseconds: 50_000_000) // 20 Hz
            }
        }
    }

    /// Called when the joystick is released — stop the camera.
    func endDrive() {
        driveTask?.cancel()
        driveTask = nil
        currentPanTilt = (0, 0)
        isDriving = false
        receiver.send(.panTilt(pan: 0, tilt: 0))
    }

    // MARK: Zoom / Focus / Iris

    func zoom(speed: Float) { receiver.send(.zoom(speed: speed)) }
    func stopZoom() { receiver.send(.zoom(speed: 0)) }
    func setZoom(_ value: Float) { receiver.send(.zoomAbsolute(value)) }

    func focus(speed: Float) { receiver.send(.focus(speed: speed)) }
    func stopFocus() { receiver.send(.focus(speed: 0)) }
    func setAutoFocus(_ on: Bool) { receiver.send(.autoFocus(on)) }

    func iris(speed: Float) { receiver.send(.iris(speed: speed)) }
    func setAutoIris(_ on: Bool) { receiver.send(.autoIris(on)) }

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
