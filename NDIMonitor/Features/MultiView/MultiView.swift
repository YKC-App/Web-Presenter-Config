//
//  MultiView.swift
//  NDIMonitor
//
//  Deliverable #3: the multi-view grid + Tally display.
//
//  Renders the active NDI sources in a grid (1×1 / 2×2 / 3×3 / 4×4). Each tile
//  shows live video via `NDIVideoView`, a Tally border (red = Program,
//  green = Preview), the source name, live FPS, and quick PG/PV buttons.
//

import SwiftUI

struct MultiView: View {
    @EnvironmentObject private var ndiManager: NDIManager
    @EnvironmentObject private var tallyManager: TallyManager
    @EnvironmentObject private var appState: AppState

    /// Cache of per-tile view models so they survive grid re-layouts.
    @StateObject private var registry = TileRegistry()

    var body: some View {
        GeometryReader { geo in
            let columns = appState.layout.columns
            let tiles = visibleTiles
            let spacing: CGFloat = 6
            let cellWidth = (geo.size.width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
            let cellHeight = cellWidth * 9 / 16

            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(cellWidth), spacing: spacing), count: columns),
                          spacing: spacing) {
                    ForEach(tiles) { tile in
                        MultiViewTile(tile: tile)
                            .frame(width: cellWidth, height: cellHeight)
                            // Double-tap opens the full-screen PTZ control (the
                            // grid preview is small); single tap just selects.
                            .onTapGesture(count: 2) { appState.fullScreenSourceID = tile.id }
                            .onTapGesture { appState.selectedSourceID = tile.id }
                    }
                }
                .padding(spacing)
            }
            .background(Color.black)
        }
        .overlay {
            if ndiManager.activeSourceIDs.isEmpty {
                EmptyStateView(title: "No sources in the multi-view",
                               systemImage: "rectangle.on.rectangle.slash",
                               message: "Add sources from the sidebar to start monitoring.")
                    .foregroundStyle(.white)
            }
        }
        .onChange(of: ndiManager.activeSourceIDs) { ids in
            registry.reconcile(ids: ids, manager: ndiManager)
        }
        .onAppear { registry.reconcile(ids: ndiManager.activeSourceIDs, manager: ndiManager) }
    }

    /// Tiles for the active sources, capped to the layout's capacity.
    private var visibleTiles: [TileViewModel] {
        ndiManager.activeSourceIDs
            .prefix(appState.layout.capacity)
            .compactMap { registry.tile(for: $0) }
    }
}

/// One grid cell: video + Tally border + overlay chrome.
private struct MultiViewTile: View {
    @ObservedObject var tile: TileViewModel
    @EnvironmentObject private var tallyManager: TallyManager
    @EnvironmentObject private var appState: AppState

    private var tally: NDITally { tallyManager.tally(for: tile.id) }

    private var borderColor: Color {
        if tally.onProgram { return .red }
        if tally.onPreview { return .green }
        return appState.selectedSourceID == tile.id ? .accentColor : .clear
    }

    var body: some View {
        ZStack {
            NDIVideoView(sink: tile.frameSink)
                .background(Color.black)

            if !tile.isConnected {
                ProgressView().tint(.white)
            }

            VStack {
                topBar
                Spacer()
                bottomBar
            }
            .padding(6)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(borderColor, lineWidth: tally.onProgram || tally.onPreview ? 4 : 2)
        )
        .animation(.easeInOut(duration: 0.15), value: borderColor)
    }

    private var topBar: some View {
        HStack(spacing: 4) {
            if tally.onProgram { TallyChip(text: "PGM", color: .red) }
            if tally.onPreview { TallyChip(text: "PVW", color: .green) }
            Spacer()
            Text(String(format: "%.0f fps", tile.measuredFPS))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.white.opacity(0.7))
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(.black.opacity(0.4), in: Capsule())
        }
    }

    private var bottomBar: some View {
        HStack {
            Text(tile.source.streamName)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(.white)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(.black.opacity(0.5), in: Capsule())
            Spacer()
            Button("PGM") { tallyManager.setProgram(tile.id) }
                .buttonStyle(TallyButtonStyle(color: .red))
            Button("PVW") { tallyManager.setPreview(tile.id) }
                .buttonStyle(TallyButtonStyle(color: .green))
        }
    }
}

private struct TallyChip: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text)
            .font(.caption2.weight(.heavy))
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(color, in: Capsule())
            .foregroundStyle(.white)
    }
}

private struct TallyButtonStyle: ButtonStyle {
    let color: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(configuration.isPressed ? 1 : 0.7), in: Capsule())
    }
}
