//
//  RootView.swift
//  NDIMonitor
//
//  Top-level iPad layout: a source browser sidebar, the multi-view monitor in
//  the centre, and a context inspector (PTZ / KVM / Auto-angle) for the
//  selected source on the trailing edge.
//

import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var ndiManager: NDIManager

    @State private var showInspector = true

    var body: some View {
        NavigationSplitView {
            SourceListView()
                .navigationTitle("NDI Sources")
        } detail: {
            HStack(spacing: 0) {
                MultiView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if showInspector, let id = appState.selectedSourceID,
                   let source = ndiManager.source(for: id) {
                    Divider()
                    ControlInspector(source: source)
                        .frame(width: 360)
                        .transition(.move(edge: .trailing))
                }
            }
            .toolbar { toolbarContent }
            .navigationTitle("Multi-View")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task { appState.start() }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker("Layout", selection: $appState.layout) {
                ForEach(MultiViewLayout.allCases) { layout in
                    Label(layout.rawValue, systemImage: layout.systemImage).tag(layout)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 320)
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                withAnimation { showInspector.toggle() }
            } label: {
                Image(systemName: "sidebar.trailing")
            }
        }
    }
}

/// Routes the inspector to the right control surface for the selected source.
private struct ControlInspector: View {
    let source: NDISource
    @EnvironmentObject private var ndiManager: NDIManager
    @State private var tab: Tab = .ptz

    enum Tab: String, CaseIterable { case ptz = "PTZ", kvm = "KVM", auto = "Auto" }

    var body: some View {
        VStack(spacing: 12) {
            Text(source.streamName).font(.headline)
            Picker("", selection: $tab) {
                ForEach(availableTabs, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            if let receiver = ndiManager.receiver(for: source.id) {
                switch tab {
                case .ptz:  PTZControlView(receiver: receiver)
                case .kvm:  KVMTrackpadView(receiver: receiver)
                case .auto: AutoAnglePanel(receiver: receiver)
                }
            } else {
                EmptyStateView(title: "Not monitoring",
                               systemImage: "play.slash",
                               message: "Add this source to the multi-view to control it.")
            }
            Spacer()
        }
        .padding()
        .onAppear { tab = availableTabs.first ?? .ptz }
    }

    private var availableTabs: [Tab] {
        var tabs: [Tab] = []
        if source.supportsPTZ { tabs.append(.ptz); tabs.append(.auto) }
        if source.supportsKVM { tabs.append(.kvm) }
        return tabs.isEmpty ? [.ptz] : tabs
    }
}
