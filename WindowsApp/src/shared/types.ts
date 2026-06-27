// Shared type definitions used by both main process and renderer.
// Must contain only plain data types (no Electron/Node/React imports).

export interface NdiSource {
  id: string;           // Unique: "<name> (<address>)"
  streamName: string;   // e.g. "CAM1"
  machineName: string;  // e.g. "SWITCHER-PC"
  hasPtz: boolean;
  hasTally: boolean;
  hasKvm: boolean;
}

export interface VideoFrame {
  sourceId: string;
  width: number;
  height: number;
  /** RGBA pixel data (width * height * 4 bytes). Transferred as Buffer. */
  data: Uint8Array;
  timestampMs: number;
}

export interface TallyState {
  sourceId: string;
  program: boolean;
  preview: boolean;
}

// ---- PTZ ----

export type WhiteBalanceMode = 'auto' | 'indoor' | 'outdoor' | 'oneshot' | 'manual';

export interface NDIPTZStatus {
  autoFocus: boolean;
  iris: number;        // 0…1
  autoIris: boolean;
  whiteBalance: WhiteBalanceMode;
  wbRed: number;       // 0…1
  wbBlue: number;      // 0…1
}

export type PtzCommandType =
  | 'panTilt'
  | 'zoom'
  | 'autoFocus'
  | 'irisAbsolute'
  | 'autoIris'
  | 'whiteBalance'
  | 'whiteBalanceManual'
  | 'recallPreset'
  | 'storePreset';

export interface PtzCommand {
  type: PtzCommandType;
  pan?: number;
  tilt?: number;
  speed?: number;
  value?: number;
  on?: boolean;
  mode?: WhiteBalanceMode;
  red?: number;
  blue?: number;
  presetIndex?: number;
}

// ---- Multi-view layout ----

export type GridLayout = '1x1' | '2x2' | '3x2' | '4x2';

export interface MultiViewSlot {
  index: number;
  sourceId: string | null;
}

// ---- IPC channel names ----

export const IPC = {
  // Main → Renderer (events)
  SOURCES_UPDATE:  'ndi:sources',
  FRAME:           'ndi:frame',
  TALLY_UPDATE:    'ndi:tally',

  // Renderer → Main (invocations)
  SUBSCRIBE:       'ndi:subscribe',
  UNSUBSCRIBE:     'ndi:unsubscribe',
  PTZ_COMMAND:     'ptz:command',
} as const;
