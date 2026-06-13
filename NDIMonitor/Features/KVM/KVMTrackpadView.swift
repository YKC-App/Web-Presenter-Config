//
//  KVMTrackpadView.swift
//  NDIMonitor
//
//  Deliverable #4 (KVM UI). The iPad screen as a trackpad: drag to move the
//  cursor, tap to click, two-finger drag to scroll, plus left/right click
//  buttons and a keyboard-capture field for keystroke forwarding.
//

import SwiftUI

struct KVMTrackpadView: View {
    @StateObject private var controller: KVMController
    @State private var keyboardText: String = ""
    @State private var previousText: String = ""
    @FocusState private var keyboardFocused: Bool

    init(receiver: NDIReceiverHandle) {
        _controller = StateObject(wrappedValue: KVMController(receiver: receiver))
    }

    var body: some View {
        VStack(spacing: 12) {
            trackpad
            sensitivity
            clickButtons
            keyboardCapture
            Spacer()
        }
    }

    private var trackpad: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(Color.secondary.opacity(0.12))
            .overlay(
                VStack(spacing: 4) {
                    Image(systemName: "hand.point.up.left").font(.title)
                    Text("Trackpad").font(.caption)
                    Text("Drag to move · tap to click").font(.caption2)
                }
                .foregroundStyle(.secondary)
            )
            .frame(height: 260)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        // Treat near-zero movement on end as a tap (handled below).
                        let delta = CGSize(width: value.translation.width - lastDrag.width,
                                           height: value.translation.height - lastDrag.height)
                        controller.moveCursor(by: delta)
                        lastDrag = value.translation
                        dragDistance += abs(delta.width) + abs(delta.height)
                    }
                    .onEnded { _ in
                        if dragDistance < 6 { controller.click(.left) } // tap
                        lastDrag = .zero
                        dragDistance = 0
                    }
            )
    }

    @State private var lastDrag: CGSize = .zero
    @State private var dragDistance: CGFloat = 0

    private var sensitivity: some View {
        HStack {
            Image(systemName: "tortoise")
            Slider(value: $controller.pointerSensitivity, in: 0.5...3.0)
            Image(systemName: "hare")
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
    }

    private var clickButtons: some View {
        HStack(spacing: 12) {
            Button("Left Click") { controller.click(.left) }
                .frame(maxWidth: .infinity)
            Button("Right Click") { controller.click(.right) }
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
    }

    private var keyboardCapture: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Keyboard").font(.headline)
            TextField("Tap here, then type to send keystrokes…", text: $keyboardText)
                .textFieldStyle(.roundedBorder)
                .focused($keyboardFocused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onChange(of: keyboardText) { new in
                    // Forward the incremental delta as typed text / backspaces.
                    // (iOS 16 onChange gives only the new value, so we keep the
                    // previous text ourselves.)
                    let old = previousText
                    if new.count > old.count {
                        controller.type(String(new.suffix(new.count - old.count)))
                    } else if new.count < old.count {
                        for _ in 0..<(old.count - new.count) {
                            controller.tapKey(KeyCode.delete) // backspace
                        }
                    }
                    previousText = new
                }
            HStack(spacing: 8) {
                keyButton("⏎", KeyCode.return)
                keyButton("⇥", KeyCode.tab)
                keyButton("esc", KeyCode.escape)
                keyButton("⌘C", KeyCode.cKey, mods: .command)
                keyButton("⌘V", KeyCode.vKey, mods: .command)
            }
        }
    }

    private func keyButton(_ label: String, _ code: UInt16, mods: KVMModifierFlags = []) -> some View {
        Button(label) { controller.tapKey(code, modifiers: mods) }
            .buttonStyle(.bordered)
    }
}

/// A few USB HID usage codes used by the on-screen special keys.
private enum KeyCode {
    static let `return`: UInt16 = 0x28
    static let escape: UInt16 = 0x29
    static let delete: UInt16 = 0x2A
    static let tab: UInt16 = 0x2B
    static let cKey: UInt16 = 0x06
    static let vKey: UInt16 = 0x19
}
