//
//  NDIManager.swift
//  NDIMonitor
//
//  Deliverable #2: NDI Discovery & Routing Manager.
//
//  Owns the canonical list of discovered sources and the set of *active*
//  receivers. The rest of the app talks to this object (never to the SDK
//  directly) to discover sources and to start/stop monitoring them.
//
//  Threading: this is a `@MainActor` `ObservableObject` so its published
//  state drives SwiftUI directly. Heavy work (receive loops, decoding) lives
//  inside the receivers, off the main thread.
//

import Combine
import Foundation

@MainActor
final class NDIManager: ObservableObject {

    // MARK: Published state

    /// All sources currently visible on the network, sorted for stable display.
    @Published private(set) var sources: [NDISource] = []

    /// Sources the user has chosen to monitor, in tile order.
    @Published private(set) var activeSourceIDs: [NDISource.ID] = []

    @Published private(set) var isDiscovering = false

    // MARK: Dependencies

    private let service: NDIServiceProtocol

    /// Active receivers keyed by source id. Exposed so feature controllers
    /// (PTZ/KVM/Tally/AutoAngle) can attach to a specific source's stream.
    private(set) var receivers: [NDISource.ID: NDIReceiverHandle] = [:]

    private var discoveryTask: Task<Void, Never>?

    // MARK: Init

    init(service: NDIServiceProtocol) {
        self.service = service
    }

    deinit {
        discoveryTask?.cancel()
    }

    // MARK: Discovery

    func startDiscovery() {
        guard !isDiscovering else { return }
        isDiscovering = true
        service.startDiscovery()

        discoveryTask = Task { [weak self] in
            guard let self else { return }
            for await snapshot in self.service.discoveredSources {
                if Task.isCancelled { break }
                self.apply(snapshot: snapshot)
            }
        }
    }

    func stopDiscovery() {
        discoveryTask?.cancel()
        discoveryTask = nil
        service.stopDiscovery()
        isDiscovering = false
    }

    /// Merge a discovery snapshot into our list, preserving previously-learned
    /// capabilities (the Find API may report a source before we connect and
    /// discover that it is, say, PTZ-capable).
    private func apply(snapshot: [NDISource]) {
        var merged = snapshot
        for i in merged.indices {
            if let known = sources.first(where: { $0.id == merged[i].id }) {
                merged[i].capabilities.formUnion(known.capabilities)
            }
        }
        sources = merged.sorted { $0.ndiName.localizedCaseInsensitiveCompare($1.ndiName) == .orderedAscending }

        // Drop active selections whose source vanished from the network.
        let live = Set(sources.map(\.id))
        for id in activeSourceIDs where !live.contains(id) {
            stopMonitoring(id)
        }
    }

    // MARK: Routing (start / stop monitoring)

    /// Resolve a source by id from the current discovery list.
    func source(for id: NDISource.ID) -> NDISource? {
        sources.first { $0.id == id }
    }

    func receiver(for id: NDISource.ID) -> NDIReceiverHandle? {
        receivers[id]
    }

    /// Start monitoring a source: opens a receiver and adds it to the tile order.
    @discardableResult
    func startMonitoring(_ source: NDISource) -> NDIReceiverHandle {
        if let existing = receivers[source.id] { return existing }
        let receiver = service.makeReceiver(for: source)
        receivers[source.id] = receiver
        if !activeSourceIDs.contains(source.id) {
            activeSourceIDs.append(source.id)
        }
        return receiver
    }

    func toggleMonitoring(_ source: NDISource) {
        if receivers[source.id] != nil {
            stopMonitoring(source.id)
        } else {
            startMonitoring(source)
        }
    }

    func stopMonitoring(_ id: NDISource.ID) {
        receivers[id]?.stop()
        receivers[id] = nil
        activeSourceIDs.removeAll { $0 == id }
    }

    func stopAll() {
        for receiver in receivers.values { receiver.stop() }
        receivers.removeAll()
        activeSourceIDs.removeAll()
    }

    /// Reorder tiles (drag-and-drop in the multi-view).
    func moveActiveSource(from offsets: IndexSet, to destination: Int) {
        activeSourceIDs.move(fromOffsets: offsets, toOffset: destination)
    }

    func isMonitoring(_ id: NDISource.ID) -> Bool {
        receivers[id] != nil
    }
}
