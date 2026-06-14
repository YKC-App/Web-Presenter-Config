//
//  LibNDIService.swift
//  NDIMonitor
//
//  Real implementation of `NDIServiceProtocol` against the NDI SDK's C API.
//  This is the ONLY file that imports `NDISDK`. It is compiled only when the
//  `USE_REAL_NDI` flag is set (see docs/NDI_SDK_INTEGRATION.md), so the rest of
//  the project builds and previews without the proprietary binary.
//
//  The bodies below show the intended SDK call sites. They are written against
//  the documented `NDIlib_*` C API; wire them up once the SDK module is added.
//

#if USE_REAL_NDI

import CoreMedia
import CoreVideo
import Foundation
import NDISDK

final class LibNDIService: NDIServiceProtocol {

    private var finder: NDIlib_find_instance_t?
    private var continuation: AsyncStream<[NDISource]>.Continuation?
    private var discoveryTask: Task<Void, Never>?

    lazy var discoveredSources: AsyncStream<[NDISource]> = AsyncStream { self.continuation = $0 }

    init?() {
        guard NDIlib_is_supported_CPU(), NDIlib_initialize() else { return nil }
    }

    deinit {
        if let finder { NDIlib_find_destroy(finder) }
        NDIlib_destroy()
    }

    // MARK: Discovery

    func startDiscovery() {
        var settings = NDIlib_find_create_t()
        settings.show_local_sources = true
        finder = NDIlib_find_create_v2(&settings)
        guard let finder else { return }

        discoveryTask = Task.detached { [weak self] in
            while !Task.isCancelled {
                // Block up to 1s for the source list to change, then read it.
                _ = NDIlib_find_wait_for_sources(finder, 1000)
                var count: UInt32 = 0
                guard let raw = NDIlib_find_get_current_sources(finder, &count) else { continue }
                var result: [NDISource] = []
                for i in 0..<Int(count) {
                    let s = raw[i]
                    let name = String(cString: s.p_ndi_name)
                    let url = s.p_url_address.map { String(cString: $0) }
                    result.append(NDISource(ndiName: name, url: url))
                }
                self?.continuation?.yield(result)
            }
        }
    }

    func stopDiscovery() {
        discoveryTask?.cancel()
        discoveryTask = nil
    }

    func makeReceiver(for source: NDISource) -> NDIReceiverHandle {
        LibNDIReceiver(source: source)
    }
}

/// Per-source receive loop backed by `NDIlib_recv_*`.
private final class LibNDIReceiver: NDIReceiverHandle {
    let source: NDISource
    private let hub = ReceiverEventHub()
    var events: AsyncStream<NDIReceiverEvent> { hub.subscribe() }
    private var recv: NDIlib_recv_instance_t?
    private var task: Task<Void, Never>?

    init(source: NDISource) {
        self.source = source
        connect()
    }

    private func connect() {
        var recvCreate = NDIlib_recv_create_v3_t()
        // Request BGRA so frames map 1:1 to kCVPixelFormatType_32BGRA and the
        // AVSampleBufferDisplayLayer renderer can display them with a simple copy.
        recvCreate.color_format = NDIlib_recv_color_format_BGRX_BGRA
        recvCreate.bandwidth = NDIlib_recv_bandwidth_highest
        // Pin the receiver to this source by name.
        source.ndiName.withCString { namePtr in
            var src = NDIlib_source_t()
            src.p_ndi_name = namePtr
            recvCreate.source_to_connect_to = src
            recv = NDIlib_recv_create_v3(&recvCreate)
        }
        guard recv != nil else { return }
        hub.publish(.connection(true))
        startReceiveLoop()
    }

    private func startReceiveLoop() {
        task = Task.detached { [weak self] in
            guard let self, let recv = self.recv else { return }
            while !Task.isCancelled {
                var video = NDIlib_video_frame_v2_t()
                var meta = NDIlib_metadata_frame_t()
                let type = NDIlib_recv_capture_v2(recv, &video, nil, &meta, 100)
                switch type {
                case NDIlib_frame_type_video:
                    if let buffer = Self.pixelBuffer(from: video) {
                        let frame = NDIVideoFrame(
                            pixelBuffer: buffer,
                            timestamp: CMTime(value: video.timecode, timescale: 10_000_000),
                            width: Int(video.xres), height: Int(video.yres))
                        self.hub.publish(.video(frame))
                    }
                    NDIlib_recv_free_video_v2(recv, &video)
                case NDIlib_frame_type_metadata:
                    if let p = meta.p_data { self.hub.publish(.metadata(String(cString: p))) }
                    NDIlib_recv_free_metadata(recv, &meta)
                default:
                    break
                }
            }
            NDIlib_recv_destroy(recv)
        }
    }

    /// Copy the SDK's BGRA frame memory into a CVPixelBuffer for display.
    ///
    /// We request `NDIlib_recv_color_format_BGRX_BGRA`, so `frame.p_data` is
    /// 32-bit BGRA. A row-by-row copy (honouring the source stride) is robust
    /// and avoids holding SDK-owned memory past `NDIlib_recv_free_video_v2`.
    private static func pixelBuffer(from frame: NDIlib_video_frame_v2_t) -> CVPixelBuffer? {
        guard let src = frame.p_data else { return nil }
        let width = Int(frame.xres)
        let height = Int(frame.yres)
        guard width > 0, height > 0 else { return nil }

        var pb: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
            kCVPixelBufferMetalCompatibilityKey: true,
        ]
        guard CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                                  kCVPixelFormatType_32BGRA,
                                  attrs as CFDictionary, &pb) == kCVReturnSuccess,
              let buffer = pb else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let dst = CVPixelBufferGetBaseAddress(buffer) else { return nil }

        let dstStride = CVPixelBufferGetBytesPerRow(buffer)
        let srcStride = Int(frame.line_stride_in_bytes)
        let rowBytes = min(dstStride, srcStride)
        for y in 0..<height {
            memcpy(dst.advanced(by: y * dstStride),
                   src.advanced(by: y * srcStride),
                   rowBytes)
        }
        return buffer
    }

    func send(_ command: PTZCommand) {
        guard let recv else { return }
        switch command {
        case .panTilt(let pan, let tilt):
            NDIlib_recv_ptz_pan_tilt_speed(recv, pan, tilt)
        case .zoom(let s):
            NDIlib_recv_ptz_zoom_speed(recv, s)
        case .zoomAbsolute(let z):
            NDIlib_recv_ptz_zoom(recv, z)
        case .focus(let s):
            NDIlib_recv_ptz_focus_speed(recv, s)
        case .focusAbsolute(let f):
            NDIlib_recv_ptz_focus(recv, f)
        case .autoFocus(let on):
            if on { NDIlib_recv_ptz_auto_focus(recv) }
        case .iris(let s):
            NDIlib_recv_ptz_exposure_iris_speed(recv, s)
        case .autoIris(let on):
            if on { NDIlib_recv_ptz_exposure_auto(recv) }
        case .recallPreset(let index, let speed):
            NDIlib_recv_ptz_recall_preset(recv, Int32(index), speed)
        case .storePreset(let index):
            NDIlib_recv_ptz_store_preset(recv, Int32(index))
        }
    }

    func send(_ command: KVMCommand) {
        // KVM is transported as NDI metadata XML on the receive connection.
        guard let recv else { return }
        let xml = KVMMetadataEncoder.xml(for: command)
        xml.withCString { ptr in
            var meta = NDIlib_metadata_frame_t()
            meta.p_data = UnsafeMutablePointer(mutating: ptr)
            meta.length = Int32(xml.utf8.count)
            NDIlib_recv_send_metadata(recv, &meta)
        }
    }

    func setTally(_ tally: NDITally) {
        guard let recv else { return }
        var t = NDIlib_tally_t()
        t.on_program = tally.onProgram
        t.on_preview = tally.onPreview
        NDIlib_recv_set_tally(recv, &t)
    }

    func stop() {
        task?.cancel()
        task = nil
        hub.publish(.connection(false))
        hub.finish()
    }
}

#endif
