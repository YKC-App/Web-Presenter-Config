//
//  AutoAnglePanel.swift
//  NDIMonitor
//
//  Deliverable #5 (UI). Controls for automatic angle control: enable toggle,
//  tracking mode, target selection among detected subjects, sensitivity, and
//  framing/zoom options. Shows a live list of detected subjects with the active
//  target highlighted.
//

import SwiftUI

struct AutoAnglePanel: View {
    @StateObject private var ptz: PTZController
    @StateObject private var auto: AutoAngleController
    @State private var mode: TrackingMode = .face

    init(receiver: NDIReceiverHandle) {
        let ptz = PTZController(receiver: receiver)
        _ptz = StateObject(wrappedValue: ptz)
        _auto = StateObject(wrappedValue: AutoAngleController(receiver: receiver, ptz: ptz))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Toggle(isOn: $auto.isEnabled) {
                    Label("Auto Tracking", systemImage: "scope")
                        .font(.headline)
                }
                .tint(.green)

                statusBadge

                Picker("Tracking", selection: $mode) {
                    ForEach(TrackingMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: mode) { new in auto.tracker.mode = new }

                VStack(alignment: .leading) {
                    Text("Sensitivity").font(.subheadline)
                    Slider(value: $auto.sensitivity, in: 0...1)
                }

                Toggle("Auto Zoom (framing)", isOn: $auto.autoZoom)

                if auto.autoZoom {
                    VStack(alignment: .leading) {
                        Text("Target fill: \(Int(auto.targetFill * 100))%").font(.subheadline)
                        Slider(value: $auto.targetFill, in: 0.15...0.7)
                    }
                }

                subjectPicker
            }
            .padding(.vertical, 4)
        }
    }

    private var statusBadge: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(auto.isEnabled ? (auto.hasLock ? .green : .yellow) : .gray)
                .frame(width: 10, height: 10)
            Text(auto.isEnabled
                 ? (auto.hasLock ? "Tracking subject" : "Searching…")
                 : "Idle")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var subjectPicker: some View {
        if !auto.subjects.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Detected (\(auto.subjects.count)) — tap to target")
                    .font(.subheadline)
                HStack(spacing: 8) {
                    ForEach(auto.subjects) { subject in
                        Button {
                            auto.tracker.selectedIndex = subject.id
                        } label: {
                            Text("#\(subject.id + 1)")
                                .font(.caption.weight(.bold))
                                .frame(width: 40, height: 40)
                                .background(
                                    auto.tracker.selectedIndex == subject.id
                                    ? Color.accentColor : Color.secondary.opacity(0.15),
                                    in: Circle())
                                .foregroundStyle(auto.tracker.selectedIndex == subject.id ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
