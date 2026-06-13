//
//  TileViewModel.swift
//  NDIMonitor
//
//  One view model per visible multi-view tile. Subscribes to its receiver's
//  event stream, forwards video frames to the renderer (out-of-band of SwiftUI
//  state to keep latency low), and publishes Tally/connection state for the UI.
//

import Combine
import Foundation

@MainActor
final class TileViewModel: ObservableObject, Identifiable {
    let source: NDISource
    nonisolated var id: NDISource.ID { source.id }

    /// Latest frame holder handed to the renderer. Not @Published — the
    /// renderer pulls from it via a display link, so SwiftUI never re-diffs on
    /// every frame.
    let frameSink = VideoFrameSink()

    @Published private(set) var tally: NDITally = .off
    @Published private(set) var isConnected = false
    @Published private(set) var measuredFPS: Double = 0

    private let receiver: NDIReceiverHandle
    private var task: Task<Void, Never>?
    private var frameTimestamps: [Date] = []

    init(source: NDISource, receiver: NDIReceiverHandle) {
        self.source = source
        self.receiver = receiver
        subscribe()
    }

    private func subscribe() {
        task = Task { [weak self] in
            guard let self else { return }
            for await event in receiver.events {
                if Task.isCancelled { break }
                switch event {
                case .video(let frame):
                    self.frameSink.push(frame)
                    self.trackFPS()
                case .tally(let tally):
                    self.tally = tally
                case .connection(let up):
                    self.isConnected = up
                case .ptzStatus, .metadata:
                    break // handled by PTZ/KVM controllers attached separately
                }
            }
        }
    }

    private func trackFPS() {
        let now = Date()
        frameTimestamps.append(now)
        frameTimestamps.removeAll { now.timeIntervalSince($0) > 1.0 }
        measuredFPS = Double(frameTimestamps.count)
    }

    deinit { task?.cancel() }
}
