//
//  MultiViewLayout.swift
//  NDIMonitor
//
//  Grid layout options for the multi-view monitor (spec 3.1).
//

import Foundation

enum MultiViewLayout: String, CaseIterable, Identifiable {
    case single   = "1×1"
    case grid2x2  = "2×2"
    case grid3x3  = "3×3"
    case grid4x4  = "4×4"

    var id: String { rawValue }

    /// Number of columns in the grid.
    var columns: Int {
        switch self {
        case .single:  return 1
        case .grid2x2: return 2
        case .grid3x3: return 3
        case .grid4x4: return 4
        }
    }

    /// Maximum number of tiles this layout shows.
    var capacity: Int { columns * columns }

    var systemImage: String {
        switch self {
        case .single:  return "square"
        case .grid2x2: return "square.grid.2x2"
        case .grid3x3: return "square.grid.3x3"
        case .grid4x4: return "square.grid.4x3.fill"
        }
    }
}
