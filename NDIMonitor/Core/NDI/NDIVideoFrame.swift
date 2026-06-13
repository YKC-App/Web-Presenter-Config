//
//  NDIVideoFrame.swift
//  NDIMonitor
//
//  SDK-agnostic representation of a decoded video frame plus the control-plane
//  events a receiver can surface (Tally, PTZ status, metadata).
//

import CoreMedia
import CoreVideo
import Foundation

/// A decoded video frame ready for rendering. We carry a `CVPixelBuffer` so the
/// renderer can hand it straight to Metal / `AVSampleBufferDisplayLayer` with no
/// extra copy.
struct NDIVideoFrame {
    let pixelBuffer: CVPixelBuffer
    /// Source presentation timestamp, used for latency measurement / sync.
    let timestamp: CMTime
    let width: Int
    let height: Int

    var size: CGSize { CGSize(width: width, height: height) }
}

/// Tally state as carried on the NDI connection.
struct NDITally: Equatable {
    var onProgram: Bool
    var onPreview: Bool

    static let off = NDITally(onProgram: false, onPreview: false)
}

/// Live PTZ status reported back by a camera (normalised −1…1 / 0…1).
struct NDIPTZStatus: Equatable {
    var pan: Float = 0      // −1 (left) … 1 (right)
    var tilt: Float = 0     // −1 (down) … 1 (up)
    var zoom: Float = 0     // 0 (wide) … 1 (tele)
    var focus: Float = 0    // 0 … 1
    var autoFocus: Bool = true
}

/// Events emitted by an `NDIReceiver` other than raw video.
enum NDIReceiverEvent {
    case video(NDIVideoFrame)
    case tally(NDITally)
    case ptzStatus(NDIPTZStatus)
    case connection(Bool)
    /// Raw NDI metadata XML (used by KVM and custom extensions).
    case metadata(String)
}
