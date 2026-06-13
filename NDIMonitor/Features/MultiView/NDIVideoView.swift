//
//  NDIVideoView.swift
//  NDIMonitor
//
//  Low-latency per-tile video renderer. Frames arrive from the receive thread
//  into a `VideoFrameSink` (drop-oldest, latest-wins). A `CADisplayLink` pulls
//  the newest frame and feeds it to an `AVSampleBufferDisplayLayer`, so video
//  rendering is fully decoupled from SwiftUI's diffing — only the latest frame
//  is ever drawn, which keeps end-to-end latency low under load (spec 3.1).
//

import AVFoundation
import CoreMedia
import SwiftUI

/// Thread-safe latest-frame holder. The receive task pushes; the display link
/// pops. Old frames are discarded (drop-oldest backpressure).
final class VideoFrameSink: @unchecked Sendable {
    private let lock = NSLock()
    private var latest: NDIVideoFrame?

    func push(_ frame: NDIVideoFrame) {
        lock.lock(); latest = frame; lock.unlock()
    }

    /// Returns and clears the latest frame, if any new frame has arrived.
    func take() -> NDIVideoFrame? {
        lock.lock(); defer { lock.unlock() }
        let f = latest
        latest = nil
        return f
    }
}

struct NDIVideoView: UIViewRepresentable {
    let sink: VideoFrameSink

    func makeUIView(context: Context) -> SampleBufferVideoView {
        SampleBufferVideoView(sink: sink)
    }

    func updateUIView(_ uiView: SampleBufferVideoView, context: Context) {
        uiView.sink = sink
    }

    static func dismantleUIView(_ uiView: SampleBufferVideoView, coordinator: ()) {
        uiView.stop()
    }
}

/// UIView backed by `AVSampleBufferDisplayLayer`, driven by a `CADisplayLink`.
final class SampleBufferVideoView: UIView {
    override class var layerClass: AnyClass { AVSampleBufferDisplayLayer.self }
    private var displayLayer: AVSampleBufferDisplayLayer { layer as! AVSampleBufferDisplayLayer }

    var sink: VideoFrameSink
    private var displayLink: CADisplayLink?

    init(sink: VideoFrameSink) {
        self.sink = sink
        super.init(frame: .zero)
        backgroundColor = .black
        displayLayer.videoGravity = .resizeAspect
        let link = CADisplayLink(target: self, selector: #selector(render))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    @objc private func render() {
        guard let frame = sink.take(),
              let sampleBuffer = Self.sampleBuffer(from: frame) else { return }
        if displayLayer.status == .failed { displayLayer.flush() }
        displayLayer.enqueue(sampleBuffer)
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    /// Wrap a CVPixelBuffer in a CMSampleBuffer for display-immediately.
    private static func sampleBuffer(from frame: NDIVideoFrame) -> CMSampleBuffer? {
        var formatDesc: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: frame.pixelBuffer,
            formatDescriptionOut: &formatDesc)
        guard let formatDesc else { return nil }

        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: frame.timestamp,
            decodeTimeStamp: .invalid)

        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: frame.pixelBuffer,
            formatDescription: formatDesc,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer)

        // Display immediately for lowest latency.
        if let sb = sampleBuffer,
           let attachments = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: true),
           CFArrayGetCount(attachments) > 0 {
            let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(dict,
                unsafeBitCast(kCMSampleAttachmentKey_DisplayImmediately, to: UnsafeRawPointer.self),
                unsafeBitCast(kCFBooleanTrue, to: UnsafeRawPointer.self))
        }
        return sampleBuffer
    }
}
