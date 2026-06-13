//
//  AppState.swift
//  NDIMonitor
//
//  Composition root (MVVM). Owns the long-lived service + managers and selects
//  the active NDI backend. This is the one place that decides between the real
//  SDK and the mock, keyed off the `USE_REAL_NDI` compilation flag.
//

import Combine
import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {

    let service: NDIServiceProtocol
    let ndiManager: NDIManager
    let tallyManager: TallyManager

    /// Layout chosen for the multi-view grid.
    @Published var layout: MultiViewLayout = .grid2x2

    /// The source currently selected for control (PTZ/KVM/auto-angle panels).
    @Published var selectedSourceID: NDISource.ID?

    init() {
        let service = AppState.makeService()
        self.service = service
        let manager = NDIManager(service: service)
        self.ndiManager = manager
        self.tallyManager = TallyManager(manager: manager)
    }

    func start() {
        ndiManager.startDiscovery()
    }

    private static func makeService() -> NDIServiceProtocol {
        #if USE_REAL_NDI
        if let real = LibNDIService() { return real }
        // Fall back to mock if the SDK fails to initialise (e.g. simulator).
        return MockNDIService()
        #else
        return MockNDIService()
        #endif
    }
}
