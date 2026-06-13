//
//  SubjectTracker.swift
//  NDIMonitor
//
//  Deliverable #5: subject detection using the Vision framework. Given a video
//  frame's pixel buffer, returns the normalised bounding box (0…1, Vision's
//  bottom-left origin) of the subject to frame. Supports face tracking and a
//  generic saliency-based "subject" mode, with selection among multiple faces.
//

import CoreGraphics
import Foundation
import Vision

enum TrackingMode: String, CaseIterable, Identifiable {
    case face = "Face"
    case humanBody = "Body"
    case saliency = "Subject"
    var id: String { rawValue }
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

    /// Runs detection synchronously on a pixel buffer and returns candidates
    /// sorted left-to-right. Call this off the main thread.
    func detect(in pixelBuffer: CVPixelBuffer) -> [TrackedSubject] {
        let request: VNImageBasedRequest
        switch mode {
        case .face:      request = VNDetectFaceRectanglesRequest()
        case .humanBody: request = VNDetectHumanRectanglesRequest()
        case .saliency:  request = VNGenerateObjectnessBasedSaliencyImageRequest()
        }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }
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

        // Sort left-to-right so `selectedIndex` is stable for the operator.
        return results.sorted { $0.boundingBox.midX < $1.boundingBox.midX }
    }

    /// The current target according to `selectedIndex`, clamped to range.
    func target(among subjects: [TrackedSubject]) -> TrackedSubject? {
        guard !subjects.isEmpty else { return nil }
        let i = max(0, min(selectedIndex, subjects.count - 1))
        return subjects[i]
    }
}
