//
//  NDIManagerTests.swift
//  NDIMonitorTests
//
//  Exercises discovery/routing against the mock service.
//

import XCTest
@testable import NDIMonitor

@MainActor
final class NDIManagerTests: XCTestCase {

    func testStartMonitoringCreatesReceiverAndRouting() {
        let manager = NDIManager(service: MockNDIService())
        let source = NDISource(ndiName: "TEST (Cam)", capabilities: [.ptz])

        XCTAssertFalse(manager.isMonitoring(source.id))
        let receiver = manager.startMonitoring(source)
        XCTAssertTrue(manager.isMonitoring(source.id))
        XCTAssertEqual(manager.activeSourceIDs, [source.id])
        XCTAssertNotNil(manager.receiver(for: source.id))
        XCTAssertEqual(receiver.source.id, source.id)

        // Toggling off removes the receiver and the tile slot.
        manager.toggleMonitoring(source)
        XCTAssertFalse(manager.isMonitoring(source.id))
        XCTAssertTrue(manager.activeSourceIDs.isEmpty)
    }

    func testStartMonitoringIsIdempotent() {
        let manager = NDIManager(service: MockNDIService())
        let source = NDISource(ndiName: "TEST (Cam)")
        let r1 = manager.startMonitoring(source)
        let r2 = manager.startMonitoring(source)
        XCTAssertTrue(r1 === r2, "Re-monitoring the same source should reuse the receiver")
        XCTAssertEqual(manager.activeSourceIDs.count, 1)
    }

    func testDiscoveryPublishesSources() async throws {
        let manager = NDIManager(service: MockNDIService())
        manager.startDiscovery()
        // Mock reveals 4 sources at ~400ms intervals; allow margin.
        try await Task.sleep(nanoseconds: 2_500_000_000)
        XCTAssertFalse(manager.sources.isEmpty)
        XCTAssertTrue(manager.sources.contains { $0.supportsPTZ })
        manager.stopDiscovery()
    }
}
