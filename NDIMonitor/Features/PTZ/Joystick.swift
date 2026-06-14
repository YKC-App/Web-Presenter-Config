//
//  Joystick.swift
//  NDIMonitor
//
//  A reusable touch joystick for PTZ pan/tilt. Reports a normalised vector
//  (−1…1, −1…1) while dragged and snaps back to centre on release. Optimised
//  for iPad touch: large hit area, spring-back, haptic on engage.
//

import SwiftUI

struct Joystick: View {
    /// Continuous vector callback while held: x = pan (−1…1), y = tilt (−1…1).
    var onChange: (_ pan: Float, _ tilt: Float) -> Void
    var onEnd: () -> Void
    /// Overall diameter of the joystick. Larger = easier touch control.
    var size: CGFloat = 220

    @State private var knob: CGSize = .zero
    private var knobSize: CGFloat { size * 0.33 }

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.secondary.opacity(0.15))
                .overlay(Circle().strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1))

            // Cross-hair guides.
            Path { p in
                p.move(to: CGPoint(x: size/2, y: 8)); p.addLine(to: CGPoint(x: size/2, y: size-8))
                p.move(to: CGPoint(x: 8, y: size/2)); p.addLine(to: CGPoint(x: size-8, y: size/2))
            }
            .stroke(Color.secondary.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

            Circle()
                .fill(Color.accentColor)
                .frame(width: knobSize, height: knobSize)
                .shadow(radius: 4)
                .offset(knob)
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let radius = (size - knobSize) / 2
                    var dx = value.translation.width
                    var dy = value.translation.height
                    let dist = sqrt(dx*dx + dy*dy)
                    if dist > radius { dx *= radius / dist; dy *= radius / dist }
                    knob = CGSize(width: dx, height: dy)
                    // Pan: negate dx so dragging right moves the camera right.
                    // Tilt: negate dy so dragging up tilts the camera up.
                    onChange(Float(-dx / radius), Float(-dy / radius))
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) { knob = .zero }
                    onEnd()
                }
        )
        .accessibilityLabel("Pan and tilt joystick")
    }
}
