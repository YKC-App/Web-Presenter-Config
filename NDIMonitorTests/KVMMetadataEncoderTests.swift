//
//  KVMMetadataEncoderTests.swift
//  NDIMonitorTests
//

import XCTest
@testable import NDIMonitor

final class KVMMetadataEncoderTests: XCTestCase {

    func testRelativeMouseMove() {
        let xml = KVMMetadataEncoder.xml(for: .mouseMove(dx: 12.5, dy: -4))
        XCTAssertTrue(xml.contains("type=\"mouse_move_rel\""))
        XCTAssertTrue(xml.contains("dx=\"12.500\""))
        XCTAssertTrue(xml.contains("dy=\"-4.000\""))
    }

    func testMouseButton() {
        let xml = KVMMetadataEncoder.xml(for: .mouseDown(button: .right))
        XCTAssertTrue(xml.contains("type=\"mouse_down\""))
        XCTAssertTrue(xml.contains("button=\"1\""))
    }

    func testKeyWithModifiers() {
        let xml = KVMMetadataEncoder.xml(for: .key(code: 0x06, down: true, modifiers: [.command]))
        XCTAssertTrue(xml.contains("type=\"key_down\""))
        XCTAssertTrue(xml.contains("code=\"6\""))
        XCTAssertTrue(xml.contains("mods=\"8\""))  // .command == 1 << 3
    }

    func testTextIsEscaped() {
        let xml = KVMMetadataEncoder.xml(for: .text("a<b>&\"c\""))
        XCTAssertTrue(xml.contains("&lt;"))
        XCTAssertTrue(xml.contains("&gt;"))
        XCTAssertTrue(xml.contains("&amp;"))
        XCTAssertTrue(xml.contains("&quot;"))
        XCTAssertFalse(xml.contains("<b>"))
    }
}
