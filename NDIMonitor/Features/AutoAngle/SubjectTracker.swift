//
//  SubjectTracker.swift
//  NDIMonitor
//
//  Deliverable #5: subject detection/tracking using the Vision framework.
//
//  Two selection methods (like the OBS Bot Tail Air):
//   • Automatic — detect faces (or bodies / salient subject) every frame.
//   • Manual region — the operator drags a box on the preview, and we track
//     that region frame-to-frame with `VNTrackObjectRequest`.
//
//  All bounding boxes are returned in Vision's convention: normalised 0…1 with
//  the origin at the bottom-left.
//

import CoreGraphics
import Foundation
import Vision

enum TrackingMode: String, CaseIterable, Identifiable {
    case face         = "Face"
    case humanBody    = "Body"
    case saliency     = "Subject"
    case manualRegion = "Region"
    var id: String { rawValue }

    var isAutomatic: Bool { self != .manualRegion }
}

/// A detected subject candidate in normalised image coordinates.
struct TrackedSubject: Identifiable {
    let id: Int
    /// Bounding box, Vision convention (origin bottom-left), normalised 0…1.
    let boundingBox: CGRect
    /// Detection confidence 0…1.
    let confidence: Float
}

final class SubjectTracker {

    var mode: TrackingMode = .face

    /// Index of the chosen target among detected candidates (left-to-right).
    var selectedIndex: Int = 0

    // Manual-region tracking state.
    private let sequenceHandler = VNSequenceRequestHandler()
    private var trackingRequest: VNTrackObjectRequest?

    /// Seed manual-region tracking with a rectangle in **top-left** normalised
    /// coordinates (0…1), as produced by a SwiftUI drag over the preview.
    func beginManualRegion(topLeftRect rect: CGRect) {
        // Convert top-left origin → Vision bottom-left origin.
        let visionRect = CGRect(x: rect.minX,
                                y: 1.0 - rect.maxY,
                                width: rect.width,
                                height: rect.height)
        let observation = VNDetectedObjectObservation(boundingBox: visionRect)
        let request = VNTrackObjectRequest(detectedObjectObservation: observation)
        request.trackingLevel = .accurate
        trackingRequest = request
        mode = .manualRegion
    }

    func clearManualRegion() {
        trackingRequest = nil
    }

    var hasManualRegion: Bool { trackingRequest != nil }

    /// Runs detection/tracking synchronously on a pixel buffer and returns
    /// candidates (sorted left-to-right for automatic modes). Call off-main.
    func detect(in pixelBuffer: CVPixelBuffer) -> [TrackedSubject] {
        if mode == .manualRegion {
            return trackManualRegion(in: pixelBuffer)
        }
        return detectAutomatic(in: pixelBuffer)
    }

    // MARK: Automatic detection

    private func detectAutomatic(in pixelBuffer: CVPixelBuffer) -> [TrackedSubject] {
        let request: VNImageBasedRequest
        switch mode {
        case .face:      request = VNDetectFaceRectanglesRequest()
        case .humanBody: request = VNDetectHumanRectanglesRequest()
        case .saliency:  request = VNGenerateObjectnessBasedSaliencyImageRequest()
        case .manualRegion: return []
        }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        do { try handler.perform([request]) } catch { return [] }
        return subjects(from: request)
    }

    private func subjects(from request: VNRequest) -> [TrackedSubject] {
        var results: [TrackedSubject] = []

        if let observations = request.results as? [VNDetectedObjectObservation],
           !(request is VNGenerateObjectnessBasedSaliencyImageRequest) {
            results = observations.enumerated().map { idx, obs in
                TrackedSubject(id: idx, boundingBox: obs.boundingBox, confidence: obs.confidence)
            }
        } else if let saliency = request.results?.first as? VNSaliencyImageObservation,
                  let salientObjects = saliency.salientObjects {
            results = salientObjects.enumerated().map { idx, obs in
                TrackedSubject(id: idx, boundingBox: obs.boundingBox, confidence: obs.confidence)
            }
        }
        return results.sorted { $0.boundingBox.midX < $1.boundingBox.midX }
    }

    // MARK: Manual-region tracking

    private func trackManualRegion(in pixelBuffer: CVPixelBuffer) -> [TrackedSubject] {
        guard let request = trackingRequest else { return [] }
        do {
            try sequenceHandler.perform([request], on: pixelBuffer, orientation: .up)
        } catch {
            return []
        }
        guard let observation = request.results?.first as? VNDetectedObjectObservation else {
            return []
        }
        // Feed the result back as the input for the next frame.
        request.inputObservation = observation
        // Drop the lock if tracking confidence collapses (subject lost).
        if observation.confidence < 0.2 { return [] }
        return [TrackedSubject(id: 0, boundingBox: observation.boundingBox, confidence: observation.confidence)]
    }

    /// The current target according to `selectedIndex`, clamped to range.
    func target(among subjects: [TrackedSubject]) -> TrackedSubject? {
        guard !subjects.isEmpty else { return nil }
        let i = max(0, min(selectedIndex, subjects.count - 1))
        return subjects[i]
    }
}
