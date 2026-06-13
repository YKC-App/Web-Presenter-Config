//
//  SourceListView.swift
//  NDIMonitor
//
//  Discovered-source browser (spec 3.1). Lists NDI sources found via mDNS and
//  lets the operator toggle which ones appear in the multi-view.
//

import SwiftUI

struct SourceListView: View {
    @EnvironmentObject private var ndiManager: NDIManager
    @EnvironmentObject private var appState: AppState

    var body: some View {
        List(ndiManager.sources) { source in
            SourceRow(source: source,
                      isMonitoring: ndiManager.isMonitoring(source.id),
                      isSelected: appState.selectedSourceID == source.id)
                .contentShape(Rectangle())
                .onTapGesture { appState.selectedSourceID = source.id }
                .swipeActions {
                    Button(ndiManager.isMonitoring(source.id) ? "Remove" : "Add") {
                        ndiManager.toggleMonitoring(source)
                    }
                    .tint(ndiManager.isMonitoring(source.id) ? .red : .accentColor)
                }
        }
        .overlay {
            if ndiManager.sources.isEmpty {
                EmptyStateView(
                    title: "Searching…",
                    systemImage: "antenna.radiowaves.left.and.right",
                    message: ndiManager.isDiscovering
                        ? "Looking for NDI sources on your network."
                        : "Discovery is stopped.")
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    ndiManager.isDiscovering ? ndiManager.stopDiscovery() : ndiManager.startDiscovery()
                } label: {
                    Image(systemName: ndiManager.isDiscovering ? "stop.circle" : "arrow.clockwise")
                }
            }
        }
    }
}

private struct SourceRow: View {
    let source: NDISource
    let isMonitoring: Bool
    let isSelected: Bool
    @EnvironmentObject private var ndiManager: NDIManager

    var body: some View {
        HStack(spacing: 12) {
            Button {
                ndiManager.toggleMonitoring(source)
            } label: {
                Image(systemName: isMonitoring ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isMonitoring ? Color.accentColor : .secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(source.streamName).font(.body.weight(.medium))
                Text(source.machineName).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 6) {
                if source.supportsPTZ { CapabilityBadge(text: "PTZ", color: .blue) }
                if source.supportsKVM { CapabilityBadge(text: "KVM", color: .purple) }
            }
        }
        .listRowBackground(isSelected ? Color.accentColor.opacity(0.15) : nil)
    }
}

private struct CapabilityBadge: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.2), in: Capsule())
            .foregroundStyle(color)
    }
}
