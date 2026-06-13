//
//  KVMMetadataEncoder.swift
//  NDIMonitor
//
//  NDI carries KVM (keyboard/video/mouse) input as metadata frames on the
//  receive connection. This encoder serialises a `KVMCommand` into the XML
//  metadata payload the SDK transmits with `NDIlib_recv_send_metadata`.
//
//  The element/attribute names below follow NDI's KVM metadata convention; if
//  your SDK build differs, this is the one place to adjust the wire format.
//

import CoreGraphics
import Foundation

enum KVMMetadataEncoder {

    static func xml(for command: KVMCommand) -> String {
        switch command {
        case .mouseMove(let dx, let dy):
            return element("ndi_kvm", ["type": "mouse_move_rel", "dx": fmt(dx), "dy": fmt(dy)])
        case .mouseMoveAbsolute(let x, let y):
            return element("ndi_kvm", ["type": "mouse_move_abs", "x": fmt(x), "y": fmt(y)])
        case .mouseDown(let button):
            return element("ndi_kvm", ["type": "mouse_down", "button": "\(button.rawValue)"])
        case .mouseUp(let button):
            return element("ndi_kvm", ["type": "mouse_up", "button": "\(button.rawValue)"])
        case .scroll(let dx, let dy):
            return element("ndi_kvm", ["type": "scroll", "dx": fmt(dx), "dy": fmt(dy)])
        case .key(let code, let down, let modifiers):
            return element("ndi_kvm", [
                "type": down ? "key_down" : "key_up",
                "code": "\(code)",
                "mods": "\(modifiers.rawValue)"
            ])
        case .text(let string):
            return element("ndi_kvm", ["type": "text", "value": escape(string)])
        }
    }

    private static func element(_ name: String, _ attrs: [String: String]) -> String {
        let body = attrs.map { "\($0.key)=\"\($0.value)\"" }.joined(separator: " ")
        return "<\(name) \(body)/>"
    }

    private static func fmt(_ v: CGFloat) -> String { String(format: "%.3f", v) }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "\"", with: "&quot;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
    }
}
