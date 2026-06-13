//
//  TileRegistry.swift
//  NDIMonitor
//
//  Owns the lifecycle of `TileViewModel`s so they persist across grid
//  re-layouts (changing 2×2 → 3×3 must not tear down and re-create the video
//  pipelines for tiles that remain visible).
//

import Foundation

@MainActor
final class TileRegistry: ObservableObject {
    /// Published so that creating/removing a tile re-renders the grid (the
    /// reconcile that adds a tile runs in `.onChange`, after the body that
    /// observed the source-list change).
    @Published private var tiles: [NDISource.ID: TileViewModel] = [:]

    func tile(for id: NDISource.ID) -> TileViewModel? {
        tiles[id]
    }

    /// Create view models for newly-active sources and discard departed ones.
    func reconcile(ids: [NDISource.ID], manager: NDIManager) {
        let active = Set(ids)
        for id in tiles.keys where !active.contains(id) {
            tiles[id] = nil
        }
        for id in ids where tiles[id] == nil {
            guard let source = manager.source(for: id),
                  let receiver = manager.receiver(for: id) else { continue }
            tiles[id] = TileViewModel(source: source, receiver: receiver)
        }
    }
}
