//
//  PTZPreset.swift
//  NDIMonitor
//
//  A named PTZ preset slot (spec 3.2: preset save/recall).
//

import Foundation

struct PTZPreset: Identifiable, Hashable {
    let id = UUID()
    /// Hardware preset slot index (0-based) sent over NDI.
    let index: Int
    var name: String

    static var defaults: [PTZPreset] {
        (0..<6).map { PTZPreset(index: $0, name: "Preset \($0 + 1)") }
    }
}
