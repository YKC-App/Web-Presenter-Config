//
//  PTZFullScreenView.swift
//  NDIMonitor
//
//  Full-screen camera control surface, opened by double-tapping a multi-view
//  tile. A large video preview on the left; all controls laid out across two
//  columns on the right so everything fits on one screen (no tabs/scrolling):
//
//   • Big pan/tilt joystick with speed + easing-curve settings
//   • Zoom / focus (press-and-hold) + auto-focus
//   • Iris/exposure (auto + manual level)
//   • White balance (auto/indoor/outdoor/one-shot presets + manual R/B)
//   • Auto subject tracking (face/body/subject + manual region selection)
//   • Presets
//
//  Opening this view never moves the camera: controls reflect last-known state
//  and only send a command on explicit interaction.
//

import SwiftUI

struct PTZFullScreenView: View {
    let source: NDISource
    var onClose: () -> Void

    @StateObject private var tile: TileViewModel
    @StateObject private var ptz: PTZController
    @StateObject private var auto: AutoAngleController

    @State private var selectingRegion = false

    init(source: NDISource, receiver: NDIReceiverHandle, onClose: @escaping () -> Void) {
        self.source = source
        self.onClose = onClose
        let ptz = PTZController(receiver: receiver)
        _tile = StateObject(wrappedValue: TileViewModel(source: source, receiver: receiver))
        _ptz = StateObject(wrappedValue: ptz)
        _auto = StateObject(wrappedValue: AutoAngleController(receiver: receiver, ptz: ptz))
    }

    var body: some View {
        VStack(spacing: 8) {
            header
            HStack(alignment: .top, spacing: 12) {
                preview
                    .frame(maxWidth: .infinity)
                columnA.frame(width: 270)
                columnB.frame(width: 290)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .background(Color.black.ignoresSafeArea())
        .foregroundStyle(.white)
        .onDisappear {
            // Stop tracking and halt the camera when leaving the screen.
            auto.isEnabled = false
            ptz.endDrive()
            ptz.stopZoom()
        }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 0) {
                Text(source.streamName).font(.title3.bold())
                Text(source.machineName).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if auto.isEnabled {
                Label(auto.hasLock ? "Tracking" : "Searching",
                      systemImage: "scope")
                    .font(.caption.bold())
                    .foregroundStyle(auto.hasLock ? .green : .yellow)
            }
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark.circle.fill").font(.title)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
    }

    // MARK: Video preview + tracking overlays

    private var preview: some View {
        GeometryReader { geo in
            ZStack {
                NDIVideoView(sink: tile.frameSink)
                    .background(Color.black)

                // Tracking box overlay (top-left normalised → view rect).
                if let box = auto.targetBoxTopLeft {
                    Rectangle()
                        .strokeBorder(.green, lineWidth: 2)
                        .frame(width: box.width * geo.size.width,
                               height: box.height * geo.size.height)
                        .position(x: (box.midX) * geo.size.width,
                                  y: (box.midY) * geo.size.height)
                }

                // Manual region selection overlay.
                if selectingRegion {
                    RegionSelector(viewSize: geo.size) { normalizedRect in
                        auto.setManualRegion(topLeftRect: normalizedRect)
                        auto.isEnabled = true
                        selectingRegion = false
                    }
                    .overlay(alignment: .top) {
                        Text("Drag to select the subject to track")
                            .font(.caption.bold())
                            .padding(6)
                            .background(.black.opacity(0.6), in: Capsule())
                            .padding(.top, 8)
                    }
                }
            }
        }
        .aspectRatio(16.0/9.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.15)))
    }

    // MARK: Column A — pan/tilt, zoom, focus

    private var columnA: some View {
        VStack(spacing: 14) {
            Joystick(
                onChange: { pan, tilt in ptz.drive(pan: pan, tilt: tilt) },
                onEnd: { ptz.endDrive() },
                size: 240
            )

            LabeledSlider(title: "PT Speed", value: $ptz.panTiltSpeed,
                          range: 0.05...1.0, minIcon: "tortoise", maxIcon: "hare")
            LabeledSlider(title: "Easing", value: $ptz.easing,
                          range: 0...1, minIcon: "bolt", maxIcon: "wind")

            HStack(spacing: 10) {
                PressHoldPad(title: "Zoom", minLabel: "W", maxLabel: "T") { s in
                    s == 0 ? ptz.stopZoom() : ptz.zoom(speed: s)
                }
                PressHoldPad(title: "Focus", minLabel: "−", maxLabel: "+") { s in
                    s == 0 ? ptz.stopFocus() : ptz.focus(speed: s)
                }
            }
            Toggle("Auto Focus", isOn: Binding(
                get: { ptz.status.autoFocus },
                set: { ptz.setAutoFocus($0) }))
                .font(.subheadline)
        }
    }

    // MARK: Column B — iris, white balance, tracking, presets

    private var columnB: some View {
        VStack(alignment: .leading, spacing: 12) {
            irisSection
            Divider().overlay(.white.opacity(0.2))
            whiteBalanceSection
            Divider().overlay(.white.opacity(0.2))
            trackingSection
            Divider().overlay(.white.opacity(0.2))
            presetSection
        }
    }

    private var irisSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Iris / Exposure").font(.subheadline.bold())
                Spacer()
                Toggle("Auto", isOn: Binding(
                    get: { ptz.status.autoIris },
                    set: { ptz.setAutoIris($0) }))
                    .labelsHidden()
                Text("Auto").font(.caption2).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                StepButton(symbol: "minus") {
                    ptz.setIris(max(0, ptz.status.iris - 0.05))
                }
                Slider(value: Binding(get: { ptz.status.iris },
                                      set: { ptz.setIris($0) }), in: 0...1)
                    .disabled(ptz.status.autoIris)
                StepButton(symbol: "plus") {
                    ptz.setIris(min(1, ptz.status.iris + 0.05))
                }
            }
            .opacity(ptz.status.autoIris ? 0.4 : 1)
        }
    }

    private var whiteBalanceSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("White Balance").font(.subheadline.bold())
            // Preset modes.
            HStack(spacing: 4) {
                ForEach(WhiteBalanceMode.allCases) { mode in
                    Button {
                        ptz.setWhiteBalance(mode)
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: mode.systemImage).font(.caption)
                            Text(mode.rawValue).font(.system(size: 9))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(ptz.status.whiteBalance == mode
                                    ? Color.accentColor : Color.white.opacity(0.1),
                                    in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
            }
            if ptz.status.whiteBalance == .manual {
                manualWBSliders
            }
        }
    }

    private var manualWBSliders: some View {
        VStack(spacing: 4) {
            wbSlider(label: "R", color: .red, value: ptz.status.wbRed) { r in
                ptz.setWhiteBalanceManual(red: r, blue: ptz.status.wbBlue)
            }
            wbSlider(label: "B", color: .blue, value: ptz.status.wbBlue) { b in
                ptz.setWhiteBalanceManual(red: ptz.status.wbRed, blue: b)
            }
        }
    }

    private func wbSlider(label: String, color: Color, value: Float,
                          onChange: @escaping (Float) -> Void) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.caption.bold()).foregroundStyle(color).frame(width: 14)
            Slider(value: Binding(get: { value }, set: { onChange($0) }), in: 0...1)
            Text(String(format: "%.0f", value * 100)).font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary).frame(width: 26)
        }
    }

    private var trackingSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Auto Tracking").font(.subheadline.bold())
                Spacer()
                Toggle("", isOn: $auto.isEnabled).labelsHidden().tint(.green)
            }
            Picker("", selection: Binding(
                get: { auto.trackingMode },
                set: { newMode in
                    auto.trackingMode = newMode
                    if newMode == .manualRegion { selectingRegion = true }
                })) {
                ForEach(TrackingMode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            if auto.trackingMode == .manualRegion {
                Button {
                    selectingRegion = true
                } label: {
                    Label("Select region on preview", systemImage: "rectangle.dashed")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .tint(.white)
            }

            LabeledSlider(title: "Sensitivity", value: $auto.sensitivity,
                          range: 0...1, minIcon: "minus", maxIcon: "plus")
            Toggle("Auto Zoom (framing)", isOn: $auto.autoZoom).font(.caption)
        }
    }

    private var presetSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Presets · tap recall / hold store").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 5) {
                ForEach(ptz.presets) { preset in
                    Button {
                        ptz.recall(preset)
                    } label: {
                        Text("\(preset.index + 1)")
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity, minHeight: 34)
                            .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .onLongPressGesture { ptz.store(preset) }
                }
            }
        }
    }
}

// MARK: - Reusable compact controls

/// Slider row with a title, value readout, and min/max icons.
private struct LabeledSlider: View {
    let title: String
    @Binding var value: Float
    let range: ClosedRange<Float>
    let minIcon: String
    let maxIcon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.caption.weight(.medium))
                Spacer()
                Text(String(format: "%.0f%%", value * 100))
                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                Image(systemName: minIcon).font(.caption2).foregroundStyle(.secondary)
                Slider(value: $value, in: range)
                Image(systemName: maxIcon).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

/// A small −/+ press-and-hold pad that drives a value bidirectionally.
private struct PressHoldPad: View {
    let title: String
    let minLabel: String
    let maxLabel: String
    let onSpeed: (Float) -> Void

    var body: some View {
        VStack(spacing: 4) {
            Text(title).font(.caption.weight(.medium))
            HStack(spacing: 6) {
                holdButton(minLabel, -0.6)
                holdButton(maxLabel, 0.6)
            }
        }
    }

    private func holdButton(_ label: String, _ speed: Float) -> some View {
        Text(label)
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in onSpeed(speed) }
                    .onEnded { _ in onSpeed(0) }
            )
    }
}

private struct StepButton: View {
    let symbol: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.caption.bold())
                .frame(width: 30, height: 30)
                .background(Color.white.opacity(0.12), in: Circle())
        }
        .buttonStyle(.plain)
    }
}

/// Transparent overlay that lets the operator drag out a rectangle; reports the
/// rect in top-left normalised (0…1) coordinates relative to `viewSize`.
private struct RegionSelector: View {
    let viewSize: CGSize
    let onSelect: (CGRect) -> Void

    @State private var start: CGPoint?
    @State private var rect: CGRect = .zero

    var body: some View {
        ZStack {
            Color.black.opacity(0.15)
            if rect != .zero {
                Rectangle()
                    .strokeBorder(.yellow, lineWidth: 2)
                    .background(Color.yellow.opacity(0.1))
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { v in
                    if start == nil { start = v.startLocation }
                    guard let s = start else { return }
                    rect = CGRect(x: min(s.x, v.location.x),
                                  y: min(s.y, v.location.y),
                                  width: abs(v.location.x - s.x),
                                  height: abs(v.location.y - s.y))
                }
                .onEnded { _ in
                    guard viewSize.width > 0, viewSize.height > 0, rect.width > 8, rect.height > 8 else {
                        start = nil; rect = .zero; return
                    }
                    let norm = CGRect(x: rect.minX / viewSize.width,
                                      y: rect.minY / viewSize.height,
                                      width: rect.width / viewSize.width,
                                      height: rect.height / viewSize.height)
                    onSelect(norm)
                    start = nil
                    rect = .zero
                }
        )
    }
}
