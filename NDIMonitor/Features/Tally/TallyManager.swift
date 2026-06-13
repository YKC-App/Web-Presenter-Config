//
//  TallyManager.swift
//  NDIMonitor
//
//  Deliverable #4 (Tally). Aggregates per-source Tally state (Program/Preview)
//  observed on each receiver, and lets the operator *push* Tally to sources
//  (e.g. when this iPad acts as the switcher surface). Program = red border,
//  Preview = green border in the multi-view.
//

import Combine
import Foundation

@MainActor
final class TallyManager: ObservableObject {
    /// Current Tally per source id.
    @Published private(set) var states: [NDISource.ID: NDITally] = [:]

    private unowned let manager: NDIManager
    private var tasks: [NDISource.ID: Task<Void, Never>] = [:]
    private var cancellable: AnyCancellable?

    init(manager: NDIManager) {
        self.manager = manager
        // Observe the active-source set so we attach/detach Tally listeners.
        cancellable = manager.$activeSourceIDs
            .receive(on: RunLoop.main)
            .sink { [weak self] ids in self?.reconcile(active: ids) }
    }

    func tally(for id: NDISource.ID) -> NDITally {
        states[id] ?? .off
    }

    /// Operator action: mark a source as on Program (and clear others' Program
    /// when `exclusive`, mirroring a real switcher bus).
    func setProgram(_ id: NDISource.ID, exclusive: Bool = true) {
        if exclusive {
            for key in states.keys where key != id {
                states[key]?.onProgram = false
                push(key)
            }
        }
        var t = states[id] ?? .off
        t.onProgram = true
        states[id] = t
        push(id)
    }

    func setPreview(_ id: NDISource.ID, exclusive: Bool = true) {
        if exclusive {
            for key in states.keys where key != id {
                states[key]?.onPreview = false
                push(key)
            }
        }
        var t = states[id] ?? .off
        t.onPreview = true
        states[id] = t
        push(id)
    }

    func clear(_ id: NDISource.ID) {
        states[id] = .off
        push(id)
    }

    /// Send the current Tally state for `id` back to the source over NDI.
    private func push(_ id: NDISource.ID) {
        manager.receiver(for: id)?.setTally(states[id] ?? .off)
    }

    /// Listen to incoming Tally on newly-active receivers; drop departed ones.
    private func reconcile(active ids: [NDISource.ID]) {
        let activeSet = Set(ids)
        for (id, task) in tasks where !activeSet.contains(id) {
            task.cancel()
            tasks[id] = nil
            states[id] = nil
        }
        for id in ids where tasks[id] == nil {
            guard let receiver = manager.receiver(for: id) else { continue }
            tasks[id] = Task { [weak self] in
                for await event in receiver.events {
                    if case .tally(let tally) = event {
                        self?.states[id] = tally
                    }
                }
            }
        }
    }
}
