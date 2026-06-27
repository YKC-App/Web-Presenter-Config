/**
 * NdiManager — wraps the native NDI addon (or a mock in dev mode).
 *
 * The native addon (native/ndi_addon.node) is loaded when the NDI SDK DLL is
 * present.  When it's missing the mock service provides simulated sources and
 * colour-bar test frames so the UI can be developed without hardware.
 */

import * as path from 'path';
import log from 'electron-log';
import { NdiSource, VideoFrame, TallyState } from '../shared/types';

// ---- Addon interface (matches ndi_addon.cpp exports) ----

interface NdiAddon {
  init(): boolean;
  destroy(): void;
  startFind(callback: (sources: RawSource[]) => void): void;
  stopFind(): void;
  createReceiver(sourceId: string, options: ReceiverOptions): number;
  destroyReceiver(handle: number): void;
  startCapture(handle: number, callback: FrameCallback): void;
  sendPtz(handle: number, type: string, args: number[]): void;
}

interface RawSource {
  id: string;
  name: string;
  machineName: string;
}

interface ReceiverOptions {
  maxWidth: number;
  maxHeight: number;
  colorFormat: 'RGBX' | 'RGBA';
}

type FrameCallback = (
  data: Buffer,
  width: number,
  height: number,
  ts: number,
  type: 'video' | 'tally',
  tallyPgm?: boolean,
  tallyPvw?: boolean,
) => void;

// ---- Receiver tracking ----

interface ReceiverEntry {
  handle: number;
  sourceId: string;
}

const NATIVE_PATH = path.join(__dirname, '../../native/build/Release/ndi_addon.node');

function tryLoadAddon(): NdiAddon | null {
  try {
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    const addon = require(NATIVE_PATH) as NdiAddon;
    if (!addon.init()) {
      log.warn('NDI addon init() returned false — NDI runtime not available');
      return null;
    }
    log.info('NDI native addon loaded');
    return addon;
  } catch (e) {
    log.warn('NDI native addon not found — using mock service', e);
    return null;
  }
}

// ---- Mock service for development / no-SDK environments ----

class MockNdiService {
  private findCallback?: (sources: NdiSource[]) => void;
  private frameCallbacks = new Map<string, (f: VideoFrame) => void>();
  private timers: ReturnType<typeof setInterval>[] = [];

  readonly mockSources: NdiSource[] = [
    { id: 'CAM1 (192.168.1.10)', streamName: 'CAM1', machineName: '192.168.1.10', hasPtz: true, hasTally: true, hasKvm: false },
    { id: 'CAM2 (192.168.1.11)', streamName: 'CAM2', machineName: '192.168.1.11', hasPtz: true, hasTally: true, hasKvm: false },
    { id: 'PGM (192.168.1.20)',  streamName: 'PGM',  machineName: '192.168.1.20', hasPtz: false, hasTally: true, hasKvm: false },
    { id: 'KVM (192.168.1.30)',  streamName: 'KVM',  machineName: '192.168.1.30', hasPtz: false, hasTally: false, hasKvm: true },
  ];

  start(cb: (s: NdiSource[]) => void): void {
    this.findCallback = cb;
    setTimeout(() => cb(this.mockSources), 800);
  }

  subscribeFrames(sourceId: string, cb: (f: VideoFrame) => void): void {
    this.frameCallbacks.set(sourceId, cb);
    const w = 320; const h = 180;
    const t = setInterval(() => {
      const data = new Uint8Array(w * h * 4);
      const hue = (Date.now() / 30) % 360;
      const [r, g, b] = hslToRgb(hue, 0.7, 0.3 + 0.2 * Math.sin(Date.now() / 500));
      for (let i = 0; i < w * h * 4; i += 4) {
        const noise = (Math.random() * 20) | 0;
        data[i] = Math.min(255, r + noise);
        data[i+1] = Math.min(255, g + noise);
        data[i+2] = Math.min(255, b + noise);
        data[i+3] = 255;
      }
      cb({ sourceId, width: w, height: h, data, timestampMs: Date.now() });
    }, 33); // ~30fps
    this.timers.push(t);
  }

  unsubscribeFrames(sourceId: string): void {
    this.frameCallbacks.delete(sourceId);
  }

  stop(): void {
    this.timers.forEach(clearInterval);
    this.timers = [];
  }
}

// ---- NdiManager (public API) ----

export class NdiManager {
  onSourcesChange?: (sources: NdiSource[]) => void;
  onFrame?: (frame: VideoFrame) => void;
  onTally?: (tally: TallyState) => void;

  private addon: NdiAddon | null = null;
  private mock: MockNdiService | null = null;
  private receivers = new Map<string, ReceiverEntry>();
  private sources: NdiSource[] = [];

  async start(): Promise<void> {
    this.addon = tryLoadAddon();

    if (this.addon) {
      this.addon.startFind((rawSources) => {
        this.sources = rawSources.map(parsePtzCapabilities);
        this.onSourcesChange?.(this.sources);
      });
    } else {
      this.mock = new MockNdiService();
      this.mock.start((s) => {
        this.sources = s;
        this.onSourcesChange?.(s);
      });
    }
  }

  stop(): void {
    this.receivers.forEach((r) => {
      this.addon?.stopFind();
      this.addon?.destroyReceiver(r.handle);
    });
    this.receivers.clear();
    this.addon?.destroy();
    this.mock?.stop();
  }

  subscribe(sourceId: string): void {
    if (this.receivers.has(sourceId)) return;

    if (this.addon) {
      const handle = this.addon.createReceiver(sourceId, {
        maxWidth: 640,
        maxHeight: 360,
        colorFormat: 'RGBA',
      });
      this.addon.startCapture(handle, (data, width, height, ts, type, pgm, pvw) => {
        if (type === 'video') {
          this.onFrame?.({ sourceId, width, height, data: new Uint8Array(data), timestampMs: ts });
        } else if (type === 'tally') {
          this.onTally?.({ sourceId, program: !!pgm, preview: !!pvw });
        }
      });
      this.receivers.set(sourceId, { handle, sourceId });
    } else {
      this.mock?.subscribeFrames(sourceId, (f) => this.onFrame?.(f));
    }
  }

  unsubscribe(sourceId: string): void {
    const entry = this.receivers.get(sourceId);
    if (entry && this.addon) {
      this.addon.destroyReceiver(entry.handle);
    }
    this.mock?.unsubscribeFrames(sourceId);
    this.receivers.delete(sourceId);
  }

  sendPtz(sourceId: string, type: string, args: number[]): void {
    const entry = this.receivers.get(sourceId);
    if (entry && this.addon) {
      this.addon.sendPtz(entry.handle, type, args);
    }
  }
}

// ---- Helpers ----

function parsePtzCapabilities(raw: RawSource): NdiSource {
  return {
    id: raw.id,
    streamName: raw.name.split(' (')[0] ?? raw.name,
    machineName: raw.machineName,
    hasPtz: true,    // NDI SDK doesn't expose caps before connect; assume PTZ.
    hasTally: true,
    hasKvm: false,
  };
}

function hslToRgb(h: number, s: number, l: number): [number, number, number] {
  const c = (1 - Math.abs(2 * l - 1)) * s;
  const x = c * (1 - Math.abs(((h / 60) % 2) - 1));
  const m = l - c / 2;
  let r = 0, g = 0, b = 0;
  if (h < 60)  { r=c; g=x; b=0; }
  else if (h < 120) { r=x; g=c; b=0; }
  else if (h < 180) { r=0; g=c; b=x; }
  else if (h < 240) { r=0; g=x; b=c; }
  else if (h < 300) { r=x; g=0; b=c; }
  else { r=c; g=0; b=x; }
  return [((r+m)*255)|0, ((g+m)*255)|0, ((b+m)*255)|0];
}
