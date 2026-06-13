//
//  KVMController.swift
//  NDIMonitor
//
//  Deliverable #4 (KVM). Turns iPad touch + keyboard input into `KVMCommand`s
//  and forwards them to a KVM-capable NDI source. The iPad screen acts as a
//  trackpad: swipe = relative cursor move, tap = click, two-finger drag = scroll.
//

import CoreGraphics
import Foundation

@MainActor
final class KVMController: ObservableObject {

    /// Pointer acceleration applied to relative trackpad moves.
    @Published var pointerSensitivity: CGFloat = 1.6

    private let receiver: NDIReceiverHandle

    init(receiver: NDIReceiverHandle) {
        self.receiver = receiver
    }

    // MARK: Mouse (trackpad emulation)

    func moveCursor(by translation: CGSize) {
        receiver.send(.mouseMove(dx: translation.width * pointerSensitivity,
                                 dy: translation.height * pointerSensitivity))
    }

    func click(_ button: KVMMouseButton = .left) {
        receiver.send(.mouseDown(button: button))
        receiver.send(.mouseUp(button: button))
    }

    func mouseDown(_ button: KVMMouseButton = .left) { receiver.send(.mouseDown(button: button)) }
    func mouseUp(_ button: KVMMouseButton = .left) { receiver.send(.mouseUp(button: button)) }

    func scroll(by translation: CGSize) {
        receiver.send(.scroll(dx: translation.width, dy: translation.height))
    }

    // MARK: Keyboard

    func type(_ text: String) {
        receiver.send(.text(text))
    }

    func key(_ code: UInt16, down: Bool, modifiers: KVMModifierFlags = []) {
        receiver.send(.key(code: code, down: down, modifiers: modifiers))
    }

    /// Tap a key (down + up).
    func tapKey(_ code: UInt16, modifiers: KVMModifierFlags = []) {
        key(code, down: true, modifiers: modifiers)
        key(code, down: false, modifiers: modifiers)
    }
}
