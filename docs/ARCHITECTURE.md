# Architecture Design & Library Composition (Deliverable #1)

This document is the answer to the spec's first deliverable: *"アーキテクチャ設計と
ライブラリ構成"* — the high-level structure of the app and the strategy for
integrating the NDI SDK.

## 1. Goals & constraints

- **Real-time, low-latency** preview of many NDI sources at once on a single iPad.
- **Touch-first** UI optimized for iPadOS (large hit targets, gestures, joystick).
- **Testable / previewable without the proprietary SDK.** The NDI SDK is a C
  library distributed under license and cannot live in the repo, so all NDI
  access goes through a protocol. A `MockNDIService` lets the UI run in Xcode
  Previews and CI; `LibNDIService` wraps the real SDK for device builds.

## 2. Architectural pattern: MVVM + a service layer

We use **MVVM** (the spec allows MVVM *or* TCA). MVVM keeps a low dependency
footprint and pairs naturally with SwiftUI's `@Observable` / `ObservableObject`.

```
┌──────────────────────────────────────────────────────────────────┐
│ SwiftUI Views (Features/*)                                         │
│  SourceListView · MultiView · PTZControlView · KVMTrackpadView ... │
└───────────────▲───────────────────────────────────┬───────────────┘
                │ @Published state                  │ user intents
┌───────────────┴───────────────────────────────────▼───────────────┐
│ ViewModels / Controllers (ObservableObject)                        │
│  MultiViewModel · PTZController · KVMController · AutoAngleController│
└───────────────▲───────────────────────────────────┬───────────────┘
                │ frames / events                   │ commands
┌───────────────┴───────────────────────────────────▼───────────────┐
│ Service layer                                                      │
│  NDIManager (discovery + routing)                                  │
│  NDIServiceProtocol  ──► LibNDIService (real SDK) / MockNDIService  │
│  NDIReceiver (per-source receive loop)                             │
│  TallyManager                                                      │
└────────────────────────────────────────────────────────────────────┘
```

### Layer responsibilities

- **Views** — pure SwiftUI. No NDI types leak above the controller layer.
- **ViewModels / Controllers** — own state, translate UI intents into service
  calls, and publish frames/Tally/PTZ status back to the UI on the main actor.
- **Service layer**
  - `NDIManager` — Bonjour/mDNS discovery via the NDI *Find* API; keeps the
    canonical list of `NDISource`s; hands out `NDIReceiver`s (routing).
  - `NDIServiceProtocol` — the seam between app and SDK. Everything above this
    line is SDK-agnostic and unit-testable.
  - `NDIReceiver` — one per actively-monitored source; runs a background
    receive loop, decodes video to `CVPixelBuffer`, and emits PTZ/Tally/metadata.
  - `TallyManager` — aggregates Program/Preview state per source and pushes
    Tally back upstream over NDI metadata.

## 3. Concurrency model

- **Receive loops** run off the main thread (one `Task` per `NDIReceiver`,
  backed by the SDK's blocking `recv` call wrapped in `withCheckedContinuation`
  / a dedicated `DispatchQueue`).
- **Video frames** are delivered as `CVPixelBuffer` and rendered with a
  `CADisplayLink`-driven Metal/`AVSampleBufferDisplayLayer` view to keep latency
  low and avoid SwiftUI re-render churn — frames never go through `@Published`.
- **Control state** (source list, Tally, PTZ status, presets) is small and
  *does* go through `@Published` / `@MainActor`.
- **Backpressure:** each receiver keeps only the latest frame (drop-oldest), so
  a slow tile can never stall the network thread.

## 4. NDI SDK integration strategy

The official *NDI SDK for Apple Platforms* exposes a C API (`Processing.NDI.Lib.h`,
`NDIlib_*`). Integration plan:

1. Add the SDK as an **XCFramework** (or static `libndi_ios.a` + headers) to the
   Xcode project; do **not** commit the binary.
2. Expose the C headers to Swift via a **module map** (`NDISDK/module.modulemap`)
   so Swift can `import NDISDK` and call `NDIlib_initialize()` etc. directly —
   no Objective-C bridging header required.
3. Implement `LibNDIService` against that C API. It is the *only* file that
   imports `NDISDK`; the rest of the app sees `NDIServiceProtocol`.
4. Select the active service in `AppState` via a build flag (`#if USE_REAL_NDI`).

See [`NDI_SDK_INTEGRATION.md`](NDI_SDK_INTEGRATION.md) for the concrete steps.

### Mapping spec features → NDI SDK calls

| Feature | NDI SDK surface |
|---|---|
| Discovery (3.1) | `NDIlib_find_*` |
| Video receive (3.1) | `NDIlib_recv_*`, `NDIlib_video_frame_v2_t` |
| PTZ (3.2) | `NDIlib_recv_ptz_*` (pan/tilt/zoom/focus/iris, store/recall preset) |
| Auto angle (3.3) | Vision analysis of received frames → PTZ calls above |
| Tally (3.4) | `NDIlib_recv_set_tally`, `NDIlib_tally_t` |
| KVM (3.5) | `NDIlib_recv_capabilities` (KVM caps) + KVM metadata over the connection |

## 5. Module / file map

| Path | Deliverable | Role |
|---|---|---|
| `Core/NDI/NDISource.swift` | #2 | Discovered-source value type |
| `Core/NDI/NDIServiceProtocol.swift` | #2 | SDK seam |
| `Core/NDI/NDIManager.swift` | #2 | Discovery + routing manager |
| `Core/NDI/NDIReceiver.swift` | #2/#3 | Per-source receive loop |
| `Core/NDI/MockNDIService.swift` | #2 | SDK-less impl for preview/CI |
| `Core/NDI/LibNDIService.swift` | #2 | Real SDK wrapper (compiled w/ flag) |
| `Features/MultiView/*` | #3 | Grid + per-tile video render |
| `Features/Tally/*` | #4 | Tally state + borders |
| `Features/PTZ/*` | #4 | PTZ controller + joystick UI |
| `Features/KVM/*` | #4 | KVM trackpad + keyboard |
| `Features/AutoAngle/*` | #5 | Vision tracking → PTZ |

## 6. Why these choices

- **Protocol seam over the SDK** → the app builds and previews today, and CI can
  run without a licensed binary; swapping in the real SDK touches exactly one file.
- **Frames out-of-band of SwiftUI state** → predictable, low-latency rendering of
  a 3×3 grid without thrashing the SwiftUI diff engine.
- **MVVM over TCA** → smaller surface for a hardware/real-time app where most of
  the complexity is in the service layer, not in reducer composition.
