# NDI Monitor — Windows App

Electron + TypeScript + React desktop app, matching the iPad app feature set.

## Quick Start

### Prerequisites

| Tool | Link |
|---|---|
| Node.js 20+ | https://nodejs.org/ |
| NDI SDK for Windows | https://ndi.video/download-ndi-sdk/ |
| Visual Studio Build Tools (for native addon) | https://visualstudio.microsoft.com/visual-cpp-build-tools/ |

### 1. Run setup

```bat
scripts\setup.bat
```

This installs npm packages, copies NDI SDK libraries, and builds the native addon.

### 2. Development

```bat
npm run dev
```

Opens Electron with live-reloading renderer. If the NDI SDK is missing, the app
starts in **mock mode** with simulated sources and colour-bar test frames.

### 3. Build installer

```bat
scripts\build.bat
```

Produces `release\NDIMonitor-Setup-1.0.0.exe` (NSIS installer).

---

## Architecture

```
src/
  main/          Electron main process (Node.js)
    index.ts       Window creation, app lifecycle
    ndi-bridge.ts  NdiManager — wraps native addon or mock
    ipc-handlers.ts  IPC handlers for PTZ commands
  preload/
    index.ts       contextBridge IPC exposure to renderer
  renderer/      React UI (browser context)
    App.tsx
    store/       Zustand global state
    hooks/       NDI subscriptions, video frame rendering, PTZ easing
    components/  SourceList, MultiView, VideoTile, PTZControlPanel, Joystick
  shared/
    types.ts     Shared type definitions (main ↔ renderer)
native/
  ndi_addon.cc  C++ NAPI addon — NDI SDK wrapper
  binding.gyp   node-gyp build config
```

## Icon / Branding

Icons are generated from `../icons/app_icon.svg` by running:

```sh
python3 ../scripts/generate_icons.py
```

Place the generated `assets/icon.ico` (Windows) and `assets/icon.icns` (macOS)
before building.

## NDI Runtime

The app bundles `Processing.NDI.Lib.x64.dll` in the installer. If it's missing on
the target machine, the NSIS installer will offer to open the NDI Tools download page.
