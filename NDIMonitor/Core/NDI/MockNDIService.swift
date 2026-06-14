//
//  MockNDIService.swift
//  NDIMonitor
//
//  SDK-less implementation of `NDIServiceProtocol`. It synthesises a handful of
//  fake sources and generates animated test-pattern frames so the entire UI —
//  multi-view, Tally, PTZ, KVM, auto-angle — runs in Xcode Previews and CI with
//  no NDI binary present. Swap to `LibNDIService` for real hardware.
//

import CoreVideo
import CoreMedia
import Foundation

final class MockNDIService: NDIServiceProtocol {

    private let demoSources: [NDISource] = [
        NDISource(ndiName: "STUDIO-PC (Camera 1)", url: "ndi://10.0.0.11", capabilities: [.ptz, .tally]),
        NDISource(ndiName: "STUDIO-PC (Camera 2)", url: "ndi://10.0.0.12", capabilities: [.ptz, .tally]),
        NDISource(ndiName: "PRODUCTION (Program)", url: "ndi://10.0.0.20", capabilities: [.tally]),
        NDISource(ndiName: "OPERATOR-MAC (Desktop)", url: "ndi://10.0.0.30", capabilities: [.kvm, .tally]),
    ]

    private var continuation: AsyncStream<[NDISource]>.Continuation?

    lazy var discoveredSources: AsyncStream<[NDISource]> = AsyncStream { continuation in
        self.continuation = continuation
    }

    func startDiscovery() {
        // Emit sources progressively to mimic real mDNS discovery timing.
        Task { [weak self] in
            guard let self else { return }
            var revealed: [NDISource] = []
            for source in self.demoSources {
                try? await Task.sleep(nanoseconds: 400_000_000)
                revealed.append(source)
                self.continuation?.yield(revealed)
            }
        }
    }

    func stopDiscovery() {
        continuation?.yield([])
    }

    func makeReceiver(for source: NDISource) -> NDIReceiverHandle {
        MockReceiver(source: source)
    }
}

/// Generates a moving test pattern + periodic Tally/PTZ events.
private final class MockReceiver: NDIReceiverHandle {
    let source: NDISource

    private let hub = ReceiverEventHub()
    var events: AsyncStream<NDIReceiverEvent> { hub.subscribe() }
    private var task: Task<Void, Never>?
    private var ptz = NDIPTZStatus()

    init(source: NDISource) {
        self.source = source
        start()
    }

    private func start() {
        hub.publish(.connection(true))
        task = Task { [weak self] in
            var frameIndex = 0
            while !Task.isCancelled {
                guard let self else { return }
                if let buffer = TestPatternGenerator.makePixelBuffer(frame: frameIndex) {
                    let frame = NDIVideoFrame(
                        pixelBuffer: buffer,
                        timestamp: CMTime(value: CMTimeValue(frameIndex), timescale: 30),
                        width: TestPatternGenerator.width,
                        height: TestPatternGenerator.height
                    )
                    self.hub.publish(.video(frame))
                }
                // Occasionally toggle Tally so the UI shows live borders.
                if frameIndex % 150 == 0 {
                    let onProgram = (frameIndex / 150) % 2 == 0 && self.source.id.contains("Camera 1")
                    let onPreview = self.source.id.contains("Camera 2")
                    self.hub.publish(.tally(NDITally(onProgram: onProgram, onPreview: onPreview)))
                }
                frameIndex += 1
                try? await Task.sleep(nanoseconds: 33_000_000) // ~30 fps
            }
        }
    }

    func send(_ command: PTZCommand) {
        // Echo PTZ moves back as status so the joystick UI feels live.
        switch command {
        case .panTilt(let pan, let tilt):
            ptz.pan = max(-1, min(1, ptz.pan + pan * 0.05))
            ptz.tilt = max(-1, min(1, ptz.tilt + tilt * 0.05))
        case .zoom(let s):
            ptz.zoom = max(0, min(1, ptz.zoom + s * 0.05))
        case .zoomAbsolute(let z): ptz.zoom = z
        case .focus(let s): ptz.focus = max(0, min(1, ptz.focus + s * 0.05))
        case .focusAbsolute(let f): ptz.focus = f
        case .autoFocus(let on): ptz.autoFocus = on
        case .iris(let s): ptz.iris = max(0, min(1, ptz.iris + s * 0.05)); ptz.autoIris = false
        case .irisAbsolute(let v): ptz.iris = v; ptz.autoIris = false
        case .autoIris(let on): ptz.autoIris = on
        case .whiteBalance(let mode):
            ptz.whiteBalance = mode
        case .whiteBalanceManual(let r, let b):
            ptz.whiteBalance = .manual; ptz.wbRed = r; ptz.wbBlue = b
        case .recallPreset, .storePreset:
            break
        }
        hub.publish(.ptzStatus(ptz))
    }

    func send(_ command: KVMCommand) {
        // No-op in mock; a real KVM source would receive these.
    }

    func setTally(_ tally: NDITally) {
        hub.publish(.tally(tally))
    }

    func stop() {
        task?.cancel()
        task = nil
        hub.publish(.connection(false))
        hub.finish()
    }
}

/// Tiny CPU test-pattern generator (color bars + moving marker) for the mock.
enum TestPatternGenerator {
    static let width = 320
    static let height = 180

    static func makePixelBuffer(frame: Int) -> CVPixelBuffer? {
        var pb: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
        ]
        CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                            kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pb)
        guard let buffer = pb else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let bpr = CVPixelBufferGetBytesPerRow(buffer)
        let ptr = base.assumingMemoryBound(to: UInt8.self)
        let bars: [(UInt8, UInt8, UInt8)] = [
            (192,192,192),(192,192,0),(0,192,192),(0,192,0),
            (192,0,192),(192,0,0),(0,0,192),(20,20,20)
        ]
        let marker = (frame * 3) % width
        for y in 0..<height {
            for x in 0..<width {
                let (r,g,b) = bars[(x * bars.count) / width]
                let o = y * bpr + x * 4
                let hit = abs(x - marker) < 3
                ptr[o+0] = hit ? 255 : b   // B
                ptr[o+1] = hit ? 255 : g   // G
                ptr[o+2] = hit ? 255 : r   // R
                ptr[o+3] = 255             // A
            }
        }
        return buffer
    }
}
