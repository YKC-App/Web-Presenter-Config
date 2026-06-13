//
//  NDISourceTests.swift
//  NDIMonitorTests
//

import XCTest
@testable import NDIMonitor

final class NDISourceTests: XCTestCase {

    func testNameParsing() {
        let source = NDISource(ndiName: "STUDIO-PC (Camera 1)")
        XCTAssertEqual(source.machineName, "STUDIO-PC")
        XCTAssertEqual(source.streamName, "Camera 1")
        XCTAssertEqual(source.id, "STUDIO-PC (Camera 1)")
    }

    func testNameParsingWithoutParentheses() {
        let source = NDISource(ndiName: "PlainName")
        XCTAssertEqual(source.machineName, "PlainName")
        XCTAssertEqual(source.streamName, "PlainName")
    }

    func testCapabilities() {
        let source = NDISource(ndiName: "Cam", capabilities: [.ptz, .tally])
        XCTAssertTrue(source.supportsPTZ)
        XCTAssertFalse(source.supportsKVM)
        XCTAssertTrue(source.capabilities.contains(.tally))
    }

    func testLayoutCapacity() {
        XCTAssertEqual(MultiViewLayout.single.capacity, 1)
        XCTAssertEqual(MultiViewLayout.grid2x2.capacity, 4)
        XCTAssertEqual(MultiViewLayout.grid3x3.capacity, 9)
        XCTAssertEqual(MultiViewLayout.grid4x4.capacity, 16)
    }
}
