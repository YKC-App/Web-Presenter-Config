//
//  PTZControlView.swift
//  NDIMonitor
//
//  Deliverable #4 (PTZ UI). Joystick for pan/tilt, press-and-hold zoom/focus
//  controls, auto-focus toggle, and a preset grid (recall tap / store long-press).
//

import SwiftUI

struct PTZControlView: View {
    @StateObject private var controller: PTZController

    init(receiver: NDIReceiverHandle) {
        _controller = StateObject(wrappedValue: PTZController(receiver: receiver))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Joystick(
                    onChange: { pan, tilt in controller.drive(pan: pan, tilt: tilt) },
                    onEnd: { controller.endDrive() }
                )
                .padding(.top, 8)

                speedControl
                zoomFocusControls
                Divider()
                presetGrid
            }
            .padding()
        }
    }

    private var speedControl: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("PT Speed").font(.subheadline.weight(.medium))
                Spacer()
                Text(String(format: "%.0f%%", controller.panTiltSpeed * 100))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Image(systemName: "tortoise").foregroundStyle(.secondary)
                Slider(value: $controller.panTiltSpeed, in: 0.05...1.0, step: 0.05)
                Image(systemName: "hare").foregroundStyle(.secondary)
            }
        }
    }

    private var zoomFocusControls: some View {
        VStack(spacing: 16) {
            HoldDriveControl(title: "Zoom", minLabel: "W", maxLabel: "T") { speed in
                speed == 0 ? controller.stopZoom() : controller.zoom(speed: speed)
            }
            HoldDriveControl(title: "Focus", minLabel: "−", maxLabel: "+") { speed in
                speed == 0 ? controller.stopFocus() : controller.focus(speed: speed)
            }
            Toggle("Auto Focus", isOn: Binding(
                get: { controller.status.autoFocus },
                set: { controller.setAutoFocus($0) }))
        }
    }

    private var presetGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Presets").font(.headline)
            Text("Tap to recall · long-press to store")
                .font(.caption).foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(controller.presets) { preset in
                    Button {
                        controller.recall(preset)
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: "\(preset.index + 1).circle.fill").font(.title2)
                            Text(preset.name).font(.caption2).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .onLongPressGesture { controller.store(preset) }
                }
            }
        }
    }
}

/// A press-and-hold bidirectional drive control (zoom/focus/iris). Sends a
/// continuous speed while held; 0 on release.
private struct HoldDriveControl: View {
    let title: String
    let minLabel: String
    let maxLabel: String
    let onSpeed: (Float) -> Void

    @State private var speed: Float = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.subheadline.weight(.medium))
                Spacer()
                Text(String(format: "%+.0f%%", speed * 100))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                driveButton(label: minLabel, value: -0.6)
                Slider(value: Binding(get: { speed }, set: { speed = $0; onSpeed($0) }),
                       in: -1...1, step: 0.05) { editing in
                    if !editing { speed = 0; onSpeed(0) }
                }
                driveButton(label: maxLabel, value: 0.6)
            }
        }
    }

    private func driveButton(label: String, value: Float) -> some View {
        Text(label)
            .font(.headline)
            .frame(width: 44, height: 44)
            .background(Color.secondary.opacity(0.15), in: Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in onSpeed(value) }
                    .onEnded { _ in onSpeed(0) }
            )
    }
}
