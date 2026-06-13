//
//  EmptyStateView.swift
//  NDIMonitor
//
//  A small placeholder view for empty/loading states. Replaces SwiftUI's
//  `ContentUnavailableView`, which is iOS 17+, so the app stays compatible with
//  the iPadOS 16.0 deployment target (spec §2).
//

import SwiftUI

struct EmptyStateView: View {
    let title: String
    let systemImage: String
    var message: String? = nil

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
            if let message {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
