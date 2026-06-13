//
//  ReceiverEventHub.swift
//  NDIMonitor
//
//  A small multicast hub so several consumers (the multi-view tile, the Tally
//  manager, and the PTZ/KVM controllers) can each `for await` the same
//  receiver's events. A bare `AsyncStream` is single-consumer, so every
//  receiver routes its events through this hub, which fans each event out to
//  every live subscriber and returns a fresh stream per `subscribe()`.
//

import Foundation

final class ReceiverEventHub: @unchecked Sendable {
    private let lock = NSLock()
    private var subscribers: [UUID: AsyncStream<NDIReceiverEvent>.Continuation] = [:]
    private var lastConnection: NDIReceiverEvent?

    /// Returns a new stream that receives every event published from now on.
    /// Late subscribers immediately get the most recent connection state so a
    /// tile added after connect still reflects "connected".
    func subscribe() -> AsyncStream<NDIReceiverEvent> {
        // Bounded buffer: if a consumer falls behind, drop the oldest events
        // rather than growing without limit (video frames are large).
        AsyncStream(bufferingPolicy: .bufferingNewest(16)) { continuation in
            let id = UUID()
            lock.lock()
            subscribers[id] = continuation
            let replay = lastConnection
            lock.unlock()

            if let replay { continuation.yield(replay) }

            continuation.onTermination = { [weak self] _ in
                self?.lock.lock()
                self?.subscribers[id] = nil
                self?.lock.unlock()
            }
        }
    }

    func publish(_ event: NDIReceiverEvent) {
        lock.lock()
        if case .connection = event { lastConnection = event }
        let conts = Array(subscribers.values)
        lock.unlock()
        for c in conts { c.yield(event) }
    }

    func finish() {
        lock.lock()
        let conts = Array(subscribers.values)
        subscribers.removeAll()
        lock.unlock()
        for c in conts { c.finish() }
    }
}
