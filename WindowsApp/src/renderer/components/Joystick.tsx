import React, { useCallback, useRef, useState } from 'react';

interface Props {
  size?: number;
  onChange: (pan: number, tilt: number) => void;
  onEnd: () => void;
}

export function Joystick({ size = 200, onChange, onEnd }: Props): React.JSX.Element {
  const knobSize = size * 0.30;
  const radius   = (size - knobSize) / 2;

  const [knob, setKnob] = useState({ x: 0, y: 0 });
  const dragging = useRef(false);
  const origin   = useRef({ x: 0, y: 0 });

  const clamp = (dx: number, dy: number): { x: number; y: number } => {
    const dist = Math.sqrt(dx * dx + dy * dy);
    if (dist > radius) {
      const ratio = radius / dist;
      return { x: dx * ratio, y: dy * ratio };
    }
    return { x: dx, y: dy };
  };

  const onPointerDown = useCallback((e: React.PointerEvent<HTMLDivElement>): void => {
    (e.target as HTMLElement).setPointerCapture(e.pointerId);
    dragging.current = true;
    const rect = e.currentTarget.getBoundingClientRect();
    origin.current = { x: rect.left + size / 2, y: rect.top + size / 2 };
    e.preventDefault();
  }, [size]);

  const onPointerMove = useCallback((e: React.PointerEvent<HTMLDivElement>): void => {
    if (!dragging.current) return;
    const dx = e.clientX - origin.current.x;
    const dy = e.clientY - origin.current.y;
    const clamped = clamp(dx, dy);
    setKnob(clamped);
    // Negate: drag right → positive pan (camera right); drag down → positive tilt (down)
    onChange(clamped.x / radius, clamped.y / radius);
  }, [radius, onChange]);

  const onPointerUp = useCallback((): void => {
    dragging.current = false;
    setKnob({ x: 0, y: 0 });
    onEnd();
  }, [onEnd]);

  return (
    <div
      className="joystick"
      style={{ width: size, height: size }}
      onPointerDown={onPointerDown}
      onPointerMove={onPointerMove}
      onPointerUp={onPointerUp}
      onPointerCancel={onPointerUp}
    >
      {/* Crosshair guide */}
      <div className="joystick-cross" />
      {/* Knob */}
      <div
        className="joystick-knob"
        style={{
          width: knobSize, height: knobSize,
          left: `calc(50% + ${knob.x}px)`,
          top:  `calc(50% + ${knob.y}px)`,
        }}
      />
    </div>
  );
}
