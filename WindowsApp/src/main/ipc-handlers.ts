import { IpcMain } from 'electron';
import { NdiManager } from './ndi-bridge';
import { PtzCommand, IPC } from '../shared/types';

export function registerIpcHandlers(ipcMain: IpcMain, ndi: NdiManager): void {

  ipcMain.handle(IPC.SUBSCRIBE, (_event, sourceId: string) => {
    ndi.subscribe(sourceId);
  });

  ipcMain.handle(IPC.UNSUBSCRIBE, (_event, sourceId: string) => {
    ndi.unsubscribe(sourceId);
  });

  ipcMain.handle(IPC.PTZ_COMMAND, (_event, sourceId: string, cmd: PtzCommand) => {
    switch (cmd.type) {
      case 'panTilt':
        ndi.sendPtz(sourceId, 'panTilt', [cmd.pan ?? 0, cmd.tilt ?? 0]);
        break;
      case 'zoom':
        ndi.sendPtz(sourceId, 'zoom', [cmd.speed ?? 0]);
        break;
      case 'autoFocus':
        ndi.sendPtz(sourceId, 'autoFocus', [cmd.on ? 1 : 0]);
        break;
      case 'irisAbsolute':
        ndi.sendPtz(sourceId, 'irisAbsolute', [cmd.value ?? 0]);
        break;
      case 'autoIris':
        ndi.sendPtz(sourceId, 'autoIris', [cmd.on ? 1 : 0]);
        break;
      case 'whiteBalance':
        ndi.sendPtz(sourceId, 'whiteBalance', [modeIndex(cmd.mode)]);
        break;
      case 'whiteBalanceManual':
        ndi.sendPtz(sourceId, 'whiteBalanceManual', [cmd.red ?? 0, cmd.blue ?? 0]);
        break;
      case 'recallPreset':
        ndi.sendPtz(sourceId, 'recallPreset', [cmd.presetIndex ?? 0, cmd.speed ?? 0.5]);
        break;
      case 'storePreset':
        ndi.sendPtz(sourceId, 'storePreset', [cmd.presetIndex ?? 0]);
        break;
    }
  });
}

function modeIndex(mode?: string): number {
  const modes = ['auto', 'indoor', 'outdoor', 'oneshot', 'manual'];
  return modes.indexOf(mode ?? 'auto');
}
