//
//  NDICommands.swift
//  NDIMonitor
//
//  Value types for the commands the app sends *to* sources: PTZ moves, KVM
//  input, and Tally. Keeping these as plain enums/structs keeps the controller
//  layer free of any SDK types and makes them trivially testable.
//

import CoreGraphics
import Foundation

// MARK: - PTZ

/// A PTZ command. Velocities are normalised −1…1; absolute targets 0…1.
enum PTZCommand: Equatable {
    /// Continuous pan/tilt drive. `pan`/`tilt` are velocities in −1…1.
    case panTilt(pan: Float, tilt: Float)
    /// Continuous zoom drive. `speed` in −1 (wide) … 1 (tele).
    case zoom(speed: Float)
    /// Absolute zoom position 0…1.
    case zoomAbsolute(Float)
    /// Continuous focus drive. `speed` in −1…1.
    case focus(speed: Float)
    /// Absolute focus position 0…1.
    case focusAbsolute(Float)
    case autoFocus(Bool)
    /// Iris/exposure drive, −1…1.
    case iris(speed: Float)
    /// Absolute iris/exposure level, 0…1.
    case irisAbsolute(Float)
    case autoIris(Bool)
    /// Select a white-balance mode (auto / indoor / outdoor / one-shot / manual).
    case whiteBalance(WhiteBalanceMode)
    /// Manual white balance: red & blue gains, 0…1.
    case whiteBalanceManual(red: Float, blue: Float)
    /// Recall a stored preset (0-based index).
    case recallPreset(index: Int, speed: Float)
    /// Store the current position into a preset slot.
    case storePreset(index: Int)
}

/// White-balance mode, mapping to the NDI `NDIlib_recv_ptz_white_balance_*` API.
enum WhiteBalanceMode: String, CaseIterable, Identifiable, Equatable {
    case auto    = "Auto"
    case indoor  = "Indoor"
    case outdoor = "Outdoor"
    case oneshot = "1-Shot"
    case manual  = "Manual"
    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .auto:    return "wand.and.stars"
        case .indoor:  return "lightbulb"
        case .outdoor: return "sun.max"
        case .oneshot: return "camera.aperture"
        case .manual:  return "slider.horizontal.3"
        }
    }
}

// MARK: - KVM

/// Mouse/keyboard input forwarded to a KVM-capable source.
enum KVMCommand: Equatable {
    /// Relative cursor move (trackpad-style), in points.
    case mouseMove(dx: CGFloat, dy: CGFloat)
    /// Absolute move, normalised 0…1 over the remote screen.
    case mouseMoveAbsolute(x: CGFloat, y: CGFloat)
    case mouseDown(button: KVMMouseButton)
    case mouseUp(button: KVMMouseButton)
    case scroll(dx: CGFloat, dy: CGFloat)
    /// Key event. `keyCode` is a USB HID usage; `modifiers` is a bitmask.
    case key(code: UInt16, down: Bool, modifiers: KVMModifierFlags)
    /// Convenience: type a unicode string.
    case text(String)
}

enum KVMMouseButton: Int, Equatable {
    case left, right, middle
}

struct KVMModifierFlags: OptionSet, Equatable {
    let rawValue: Int
    static let shift   = KVMModifierFlags(rawValue: 1 << 0)
    static let control = KVMModifierFlags(rawValue: 1 << 1)
    static let option  = KVMModifierFlags(rawValue: 1 << 2)
    static let command = KVMModifierFlags(rawValue: 1 << 3)
}
