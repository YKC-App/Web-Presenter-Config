/**
 * PTZ controller hook — mirrors PTZController.swift's easing drive loop.
 *
 * Pan/tilt velocity is eased from 0 to the target and back, giving smooth
 * acceleration/deceleration identical to the iPad app.  The drive loop runs
 * at 20 Hz via setInterval.
 */

import { useCallback, useEffect, useRef, useState } from 'react';
import { useAppStore } from '../store/appStore';
import type { PtzCommand, NDIPTZStatus } from '../../shared/types';

interface PTZControls {
  status: NDIPTZStatus;
  panTiltSpeed: number;
  setPanTiltSpeed: (v: number) => void;
  easing: number;
  setEasing: (v: number) => void;
  drive: (pan: number, tilt: number) => void;
  endDrive: () => void;
  zoom: (speed: number) => void;
  stopZoom: () => void;
  focus: (speed: number) => void;
  stopFocus: () => void;
  setAutoFocus: (on: boolean) => void;
  setIris: (level: number) => void;
  setAutoIris: (on: boolean) => void;
  setWhiteBalance: (mode: NDIPTZStatus['whiteBalance']) => void;
  setWhiteBalanceManual: (red: number, blue: number) => void;
  recallPreset: (index: number) => void;
  storePreset: (index: number) => void;
}

const DEFAULT_STATUS: NDIPTZStatus = {
  autoFocus: true, iris: 0.5, autoIris: true,
  whiteBalance: 'auto', wbRed: 0.5, wbBlue: 0.5,
};

export function usePTZController(sourceId: string | null): PTZControls {
  const ptzStatus     = useAppStore((s) => s.ptzStatus);
  const updateStatus  = useAppStore((s) => s.updatePtzStatus);

  const [panTiltSpeed, setPanTiltSpeed] = useState(0.5);
  const [easing, setEasing]             = useState(0.35);

  const targetRef   = useRef({ pan: 0, tilt: 0 });
  const appliedRef  = useRef({ pan: 0, tilt: 0 });
  const releasedRef = useRef(true);
  const intervalRef = useRef<ReturnType<typeof setInterval> | null>(null);

  const send = useCallback((cmd: PtzCommand) => {
    if (!sourceId) return;
    void window.ndiAPI.sendPtz(sourceId, cmd);
  }, [sourceId]);

  // ---- Easing drive loop ----

  const startLoop = useCallback(() => {
    if (intervalRef.current) return;
    intervalRef.current = setInterval(() => {
      const alpha = Math.max(0.06, 1.0 - easing * 0.94);
      const ap = appliedRef.current;
      const tgt = targetRef.current;
      ap.pan  += (tgt.pan  - ap.pan)  * alpha;
      ap.tilt += (tgt.tilt - ap.tilt) * alpha;

      send({ type: 'panTilt', pan: clamp(ap.pan), tilt: clamp(ap.tilt) });

      if (releasedRef.current && Math.abs(ap.pan) < 0.01 && Math.abs(ap.tilt) < 0.01) {
        send({ type: 'panTilt', pan: 0, tilt: 0 });
        clearInterval(intervalRef.current!);
        intervalRef.current = null;
        appliedRef.current = { pan: 0, tilt: 0 };
      }
    }, 50); // 20 Hz
  }, [easing, send]);

  const drive = useCallback((pan: number, tilt: number) => {
    releasedRef.current = false;
    targetRef.current = { pan: pan * panTiltSpeed, tilt: tilt * panTiltSpeed };
    startLoop();
  }, [panTiltSpeed, startLoop]);

  const endDrive = useCallback(() => {
    releasedRef.current = true;
    targetRef.current = { pan: 0, tilt: 0 };
  }, []);

  // Stop loop on unmount.
  useEffect(() => () => {
    if (intervalRef.current) clearInterval(intervalRef.current);
  }, []);

  const status = sourceId ? (ptzStatus[sourceId] ?? DEFAULT_STATUS) : DEFAULT_STATUS;

  return {
    status,
    panTiltSpeed, setPanTiltSpeed,
    easing, setEasing,
    drive, endDrive,
    zoom:      (speed) => send({ type: 'zoom', speed }),
    stopZoom:  ()      => send({ type: 'zoom', speed: 0 }),
    focus:     (speed) => send({ type: 'zoom', speed }), // reuse zoom channel for focus speed sign
    stopFocus: ()      => send({ type: 'zoom', speed: 0 }),
    setAutoFocus: (on) => {
      updateStatus(sourceId!, { autoFocus: on });
      send({ type: 'autoFocus', on });
    },
    setIris: (level) => {
      updateStatus(sourceId!, { iris: level, autoIris: false });
      send({ type: 'irisAbsolute', value: level });
    },
    setAutoIris: (on) => {
      updateStatus(sourceId!, { autoIris: on });
      send({ type: 'autoIris', on });
    },
    setWhiteBalance: (mode) => {
      updateStatus(sourceId!, { whiteBalance: mode });
      send({ type: 'whiteBalance', mode });
    },
    setWhiteBalanceManual: (red, blue) => {
      updateStatus(sourceId!, { whiteBalance: 'manual', wbRed: red, wbBlue: blue });
      send({ type: 'whiteBalanceManual', red, blue });
    },
    recallPreset: (index) => send({ type: 'recallPreset', presetIndex: index, speed: 0.5 }),
    storePreset:  (index) => send({ type: 'storePreset', presetIndex: index }),
  };
}

const clamp = (v: number): number => Math.max(-1, Math.min(1, v));
