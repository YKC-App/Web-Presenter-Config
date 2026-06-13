//
//  NDIMonitorApp.swift
//  NDIMonitor
//
//  App entry point. Builds the service (real or mock), wires up the shared
//  managers, and presents the root scene.
//

import SwiftUI

@main
struct NDIMonitorApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environmentObject(appState.ndiManager)
                .environmentObject(appState.tallyManager)
                .preferredColorScheme(.dark)
        }
    }
}
