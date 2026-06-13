//
//  NDIServiceProtocol.swift
//  NDIMonitor
//
//  The single seam between the app and the NDI SDK. Everything above this
//  protocol is SDK-agnostic. `LibNDIService` implements it against the real C
//  SDK; `MockNDIService` implements it for previews, CI, and offline dev.
//

import Foundation

/// A live connection to one NDI source. Created by the service when the app
/// starts monitoring a source; tears down its receive loop on `stop()`.
protocol NDIReceiverHandle: AnyObject {
    var source: NDISource { get }

    /// Async stream of decoded frames + control events from this source.
    ///
    /// Each access returns a *fresh* subscription (backed by `ReceiverEventHub`),
    /// so multiple consumers — the multi-view tile, the Tally manager, and the
    /// PTZ/KVM controllers — can each `for await` independently.
    var events: AsyncStream<NDIReceiverEvent> { get }

    /// Send a PTZ command to the source (no-op if it is not PTZ-capable).
    func send(_ command: PTZCommand)

    /// Send a KVM command (no-op if the source is not KVM-capable).
    func send(_ command: KVMCommand)

    /// Push Tally state to the source (Program/Preview), per NDI semantics.
    func setTally(_ tally: NDITally)

    /// Stop the receive loop and release SDK resources.
    func stop()
}

/// The discovery + connection facade implemented by each backend.
protocol NDIServiceProtocol: AnyObject {
    /// Continuous stream of the *full* discovered-source list (debounced by the
    /// backend). Emits a new snapshot whenever sources appear/disappear.
    var discoveredSources: AsyncStream<[NDISource]> { get }

    /// Begin/stop mDNS/Bonjour discovery.
    func startDiscovery()
    func stopDiscovery()

    /// Open a receiver for a source and start its background receive loop.
    func makeReceiver(for source: NDISource) -> NDIReceiverHandle
}
