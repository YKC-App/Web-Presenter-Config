import { app, BrowserWindow, ipcMain, shell } from 'electron';
import * as path from 'path';
import log from 'electron-log';
import { NdiManager } from './ndi-bridge';
import { registerIpcHandlers } from './ipc-handlers';

log.initialize({ preload: true });
log.info('NDI Monitor starting...');

const isDev = process.env.NODE_ENV === 'development';

let mainWindow: BrowserWindow | null = null;
let ndiManager: NdiManager | null = null;

function createWindow(): void {
  mainWindow = new BrowserWindow({
    width: 1440,
    height: 900,
    minWidth: 1024,
    minHeight: 640,
    backgroundColor: '#0A1020',
    titleBarStyle: process.platform === 'darwin' ? 'hiddenInset' : 'default',
    webPreferences: {
      preload: path.join(__dirname, '../preload/index.js'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: false,
    },
    icon: path.join(app.getAppPath(), 'assets', 'icon.ico'),
    title: 'NDI Monitor',
    show: false,
  });

  if (isDev) {
    mainWindow.loadURL('http://localhost:3000');
    mainWindow.webContents.openDevTools({ mode: 'detach' });
  } else {
    mainWindow.loadFile(path.join(__dirname, '../renderer/index.html'));
  }

  mainWindow.once('ready-to-show', () => {
    mainWindow?.show();
  });

  mainWindow.webContents.setWindowOpenHandler(({ url }) => {
    shell.openExternal(url);
    return { action: 'deny' };
  });

  mainWindow.on('closed', () => {
    mainWindow = null;
  });
}

app.whenReady().then(async () => {
  createWindow();

  // Start NDI
  ndiManager = new NdiManager();
  await ndiManager.start();
  ndiManager.onSourcesChange = (sources) => {
    mainWindow?.webContents.send('ndi:sources', sources);
  };
  ndiManager.onFrame = (frame) => {
    if (!mainWindow?.isDestroyed()) {
      // Transfer ArrayBuffer to avoid copy where possible.
      mainWindow?.webContents.send('ndi:frame', {
        sourceId: frame.sourceId,
        width: frame.width,
        height: frame.height,
        timestampMs: frame.timestampMs,
        data: frame.data,
      });
    }
  };
  ndiManager.onTally = (tally) => {
    mainWindow?.webContents.send('ndi:tally', tally);
  };

  registerIpcHandlers(ipcMain, ndiManager);

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on('window-all-closed', () => {
  ndiManager?.stop();
  if (process.platform !== 'darwin') app.quit();
});

app.on('before-quit', () => {
  ndiManager?.stop();
});
