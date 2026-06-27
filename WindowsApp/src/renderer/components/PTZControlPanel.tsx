import React, { useCallback, useRef } from 'react';
import { Joystick } from './Joystick';
import { usePTZController } from '../hooks/usePTZController';
import type { NDIPTZStatus } from '../../shared/types';

interface Props {
  sourceId: string | null;
}

const WB_MODES: NDIPTZStatus['whiteBalance'][] = ['auto', 'indoor', 'outdoor', 'oneshot', 'manual'];
const WB_LABELS: Record<string, string> = {
  auto: 'Auto', indoor: 'Indoor', outdoor: 'Outdoor', oneshot: '1-Shot', manual: 'Manual',
};
const PRESETS = [0, 1, 2, 3, 4, 5];

export function PTZControlPanel({ sourceId }: Props): React.JSX.Element {
  const ptz = usePTZController(sourceId);

  const noSource = !sourceId;

  const holdStart = useCallback((cb: () => void) => {
    let timer: ReturnType<typeof setInterval>;
    return {
      onPointerDown: (e: React.PointerEvent): void => {
        (e.target as HTMLElement).setPointerCapture(e.pointerId);
        cb();
        timer = setInterval(cb, 50);
      },
      onPointerUp: (): void => clearInterval(timer),
    };
  }, []);

  if (noSource) {
    return (
      <div style={{ padding: 20, color: 'var(--text-muted)', textAlign: 'center', fontSize: 12 }}>
        Select a source to show PTZ controls
      </div>
    );
  }

  return (
    <div>
      {/* ---- Pan / Tilt Joystick ---- */}
      <div className="ptz-section">
        <div className="ptz-section-title">Pan / Tilt</div>
        <div className="joystick-wrapper">
          <Joystick
            size={220}
            onChange={(pan, tilt) => ptz.drive(pan, tilt)}
            onEnd={() => ptz.endDrive()}
          />
        </div>
        <LabeledSlider
          title="PT Speed"
          value={ptz.panTiltSpeed}
          min={0.05} max={1}
          onChange={ptz.setPanTiltSpeed}
        />
        <LabeledSlider
          title="Easing"
          value={ptz.easing}
          min={0} max={1}
          onChange={ptz.setEasing}
        />
      </div>

      <div className="divider" />

      {/* ---- Zoom / Focus ---- */}
      <div className="ptz-section">
        <div className="ptz-section-title">Zoom / Focus</div>
        <div style={{ display: 'flex', gap: 8 }}>
          <PressHoldPad
            title="Zoom"
            minLabel="W" maxLabel="T"
            onSpeed={(s) => s === 0 ? ptz.stopZoom() : ptz.zoom(s)}
          />
          <PressHoldPad
            title="Focus"
            minLabel="−" maxLabel="+"
            onSpeed={(s) => s === 0 ? ptz.stopFocus() : ptz.focus(s)}
          />
        </div>
        <div className="toggle-row" style={{ marginTop: 8 }}>
          <span className="toggle-label">Auto Focus</span>
          <input
            type="checkbox"
            checked={ptz.status.autoFocus}
            onChange={(e) => ptz.setAutoFocus(e.target.checked)}
          />
        </div>
      </div>

      <div className="divider" />

      {/* ---- Iris / Exposure ---- */}
      <div className="ptz-section">
        <div className="ptz-section-title" style={{ display: 'flex', justifyContent: 'space-between' }}>
          <span>Iris / Exposure</span>
          <label style={{ display: 'flex', alignItems: 'center', gap: 4, fontSize: 10, textTransform: 'none', letterSpacing: 0 }}>
            Auto
            <input
              type="checkbox"
              checked={ptz.status.autoIris}
              onChange={(e) => ptz.setAutoIris(e.target.checked)}
            />
          </label>
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
          <StepButton symbol="−" onClick={() => ptz.setIris(Math.max(0, ptz.status.iris - 0.05))} />
          <input
            type="range" min={0} max={1} step={0.01}
            value={ptz.status.iris}
            onChange={(e) => ptz.setIris(Number(e.target.value))}
            style={{ flex: 1 }}
          />
          <StepButton symbol="+" onClick={() => ptz.setIris(Math.min(1, ptz.status.iris + 0.05))} />
          <span style={{ fontSize: 10, color: 'var(--text-muted)', width: 28, textAlign: 'right' }}>
            {Math.round(ptz.status.iris * 100)}
          </span>
        </div>
      </div>

      <div className="divider" />

      {/* ---- White Balance ---- */}
      <div className="ptz-section">
        <div className="ptz-section-title">White Balance</div>
        <div className="wb-presets">
          {WB_MODES.map((m) => (
            <button
              key={m}
              className={`wb-btn${ptz.status.whiteBalance === m ? ' active' : ''}`}
              onClick={() => ptz.setWhiteBalance(m)}
            >
              {WB_LABELS[m]}
            </button>
          ))}
        </div>
        {ptz.status.whiteBalance === 'manual' && (
          <>
            <WBStepper label="R" colorClass="r" value={ptz.status.wbRed}
              onDec={() => ptz.setWhiteBalanceManual(Math.max(0, ptz.status.wbRed - 0.05), ptz.status.wbBlue)}
              onInc={() => ptz.setWhiteBalanceManual(Math.min(1, ptz.status.wbRed + 0.05), ptz.status.wbBlue)}
            />
            <WBStepper label="B" colorClass="b" value={ptz.status.wbBlue}
              onDec={() => ptz.setWhiteBalanceManual(ptz.status.wbRed, Math.max(0, ptz.status.wbBlue - 0.05))}
              onInc={() => ptz.setWhiteBalanceManual(ptz.status.wbRed, Math.min(1, ptz.status.wbBlue + 0.05))}
            />
          </>
        )}
      </div>

      <div className="divider" />

      {/* ---- Presets ---- */}
      <div className="ptz-section">
        <div className="ptz-section-title">Presets · tap recall / hold store</div>
        <div className="preset-grid">
          {PRESETS.map((i) => (
            <PresetButton
              key={i}
              index={i}
              onRecall={() => ptz.recallPreset(i)}
              onStore={() => ptz.storePreset(i)}
            />
          ))}
        </div>
      </div>
    </div>
  );
}

// ---- Sub-components ----

function LabeledSlider({ title, value, min, max, onChange }: {
  title: string; value: number; min: number; max: number; onChange: (v: number) => void;
}): React.JSX.Element {
  return (
    <div className="labeled-slider">
      <div className="labeled-slider-header">
        <span className="labeled-slider-title">{title}</span>
        <span className="labeled-slider-value">{Math.round(value * 100)}%</span>
      </div>
      <input
        type="range" min={min} max={max} step={0.01} value={value}
        onChange={(e) => onChange(Number(e.target.value))}
      />
    </div>
  );
}

function PressHoldPad({ title, minLabel, maxLabel, onSpeed }: {
  title: string; minLabel: string; maxLabel: string; onSpeed: (s: number) => void;
}): React.JSX.Element {
  const makeHold = (speed: number): React.PointerEventHandler => {
    let timer: ReturnType<typeof setInterval>;
    return (e: React.PointerEvent): void => {
      (e.target as HTMLElement).setPointerCapture(e.pointerId);
      onSpeed(speed);
      timer = setInterval(() => onSpeed(speed), 50);
      const up = (): void => { clearInterval(timer); onSpeed(0); window.removeEventListener('pointerup', up); };
      window.addEventListener('pointerup', up);
    };
  };
  return (
    <div className="press-hold-pad" style={{ flex: 1 }}>
      <div className="press-hold-title">{title}</div>
      <div className="press-hold-buttons">
        <div className="press-hold-btn" onPointerDown={makeHold(-0.6)}>{minLabel}</div>
        <div className="press-hold-btn" onPointerDown={makeHold(0.6)}>{maxLabel}</div>
      </div>
    </div>
  );
}

function StepButton({ symbol, onClick }: { symbol: string; onClick: () => void }): React.JSX.Element {
  return <button className="step-btn" onClick={onClick}>{symbol}</button>;
}

function WBStepper({ label, colorClass, value, onDec, onInc }: {
  label: string; colorClass: string; value: number; onDec: () => void; onInc: () => void;
}): React.JSX.Element {
  return (
    <div className="step-row">
      <span className={`step-label ${colorClass}`}>{label}</span>
      <StepButton symbol="−" onClick={onDec} />
      <span className="step-value">{Math.round(value * 100)}</span>
      <StepButton symbol="+" onClick={onInc} />
    </div>
  );
}

function PresetButton({ index, onRecall, onStore }: {
  index: number; onRecall: () => void; onStore: () => void;
}): React.JSX.Element {
  const holdRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const moved   = useRef(false);

  const onDown = (): void => {
    moved.current = false;
    holdRef.current = setTimeout(() => { moved.current = true; onStore(); }, 700);
  };
  const onUp = (): void => {
    clearTimeout(holdRef.current!);
    if (!moved.current) onRecall();
  };

  return (
    <button className="preset-btn" onPointerDown={onDown} onPointerUp={onUp}>
      {index + 1}
    </button>
  );
}

