//
//  NDISource.swift
//  NDIMonitor
//
//  A discovered NDI source on the local network. This is an SDK-agnostic value
//  type — nothing here imports the NDI SDK, so it is safe to use throughout the
//  UI and to mock in previews/tests.
//

import Foundation

/// Capabilities a source may advertise. Determines which control surfaces the
/// UI offers for a given tile (PTZ joystick, KVM trackpad, …).
struct NDISourceCapabilities: OptionSet, Hashable {
    let rawValue: Int

    static let ptz = NDISourceCapabilities(rawValue: 1 << 0)
    static let kvm = NDISourceCapabilities(rawValue: 1 << 1)
    /// The source accepts Tally state changes (Program/Preview) from receivers.
    static let tally = NDISourceCapabilities(rawValue: 1 << 2)

    static let none: NDISourceCapabilities = []
}

/// A single NDI source as reported by the discovery (Find) API.
///
/// The NDI "name" is conventionally `"<machine> (<source>)"`. We keep the raw
/// string plus the parsed parts for display.
struct NDISource: Identifiable, Hashable {
    /// Stable identity. The full NDI name is unique on a network, so we hash it.
    var id: String { ndiName }

    /// Full NDI name, e.g. `"STUDIO-PC (Camera 1)"`.
    let ndiName: String

    /// Resolved URL/address (`ip:port` or `ndi://…`) when known.
    let url: String?

    /// Capabilities advertised by the source (may be refined after connecting).
    var capabilities: NDISourceCapabilities

    init(ndiName: String, url: String? = nil, capabilities: NDISourceCapabilities = .none) {
        self.ndiName = ndiName
        self.url = url
        self.capabilities = capabilities
    }

    /// Machine portion of the NDI name (text before the first `(`).
    var machineName: String {
        guard let range = ndiName.range(of: " (") else { return ndiName }
        return String(ndiName[ndiName.startIndex..<range.lowerBound])
    }

    /// Stream/source portion (text inside the parentheses), falling back to full.
    var streamName: String {
        guard let open = ndiName.firstIndex(of: "("),
              let close = ndiName.lastIndex(of: ")"),
              open < close else { return ndiName }
        return String(ndiName[ndiName.index(after: open)..<close])
    }

    var supportsPTZ: Bool { capabilities.contains(.ptz) }
    var supportsKVM: Bool { capabilities.contains(.kvm) }
}
