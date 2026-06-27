/**
 * Preload script: exposes a safe IPC bridge to the renderer via contextBridge.
 * nodeIntegration is OFF in the renderer; this is the only channel.
 */

import { contextBridge, ipcRenderer } from 'electron';
import type { NdiSource, VideoFrame, TallyState, PtzCommand, IPC as IPCType } from '../shared/types';
import { IPC } from '../shared/types';

export type NdiAPI = typeof api;

const api = {
  // ---- Subscriptions ----
  subscribe:   (sourceId: string)                     => ipcRenderer.invoke(IPC.SUBSCRIBE, sourceId),
  unsubscribe: (sourceId: string)                     => ipcRenderer.invoke(IPC.UNSUBSCRIBE, sourceId),

  // ---- PTZ ----
  sendPtz: (sourceId: string, cmd: PtzCommand)        => ipcRenderer.invoke(IPC.PTZ_COMMAND, sourceId, cmd),

  // ---- Events → callbacks ----
  onSources: (cb: (sources: NdiSource[]) => void) => {
    const handler = (_: unknown, sources: NdiSource[]) => cb(sources);
    ipcRenderer.on(IPC.SOURCES_UPDATE, handler);
    return () => ipcRenderer.off(IPC.SOURCES_UPDATE, handler);
  },
  onFrame: (cb: (frame: VideoFrame) => void) => {
    const handler = (_: unknown, frame: VideoFrame) => cb(frame);
    ipcRenderer.on(IPC.FRAME, handler);
    return () => ipcRenderer.off(IPC.FRAME, handler);
  },
  onTally: (cb: (tally: TallyState) => void) => {
    const handler = (_: unknown, tally: TallyState) => cb(tally);
    ipcRenderer.on(IPC.TALLY_UPDATE, handler);
    return () => ipcRenderer.off(IPC.TALLY_UPDATE, handler);
  },
};

contextBridge.exposeInMainWorld('ndiAPI', api);

// Make TypeScript happy in the renderer via global augmentation.
declare global {
  interface Window {
    ndiAPI: NdiAPI;
  }
}
