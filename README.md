# Web Presenter — NDI Multi-Monitor & Control for iPad

An iPadOS application for monitoring multiple NDI® (Network Device Interface)
video sources simultaneously, with PTZ camera control, KVM control, Tally,
and AI-assisted automatic angle control.

> **Status:** Reference implementation / base codebase. The networking video
> path is built against an abstraction (`NDIServiceProtocol`) so the project
> compiles and previews **without** the proprietary NDI SDK binary. To ship,
> drop in the official *NDI SDK for Apple* and switch the active service from
> `MockNDIService` to `LibNDIService` (see `docs/NDI_SDK_INTEGRATION.md`).

## Highlights

| Spec section | Feature | Where |
|---|---|---|
| 3.1 | NDI source discovery + multi-view grid | `NDIMonitor/Features/MultiView`, `NDIMonitor/Core/NDI` |
| 3.2 | PTZ camera control (pan/tilt/zoom/focus/iris/presets) | `NDIMonitor/Features/PTZ` |
| 3.3 | Automatic angle control (Vision tracking) | `NDIMonitor/Features/AutoAngle` |
| 3.4 | Tally (Program / Preview) | `NDIMonitor/Features/Tally` |
| 3.5 | KVM control (trackpad + keyboard) | `NDIMonitor/Features/KVM` |

## Requirements

- iPadOS 16.0+
- Swift 5.9+ / Xcode 15+
- (To ship) NDI SDK for Apple Platforms

## Documentation

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — full architecture design (deliverable #1)
- [`docs/NDI_SDK_INTEGRATION.md`](docs/NDI_SDK_INTEGRATION.md) — how to drop in the real NDI SDK

## Project layout

```
NDIMonitor/
  App/            App entry point + global app state (MVVM root)
  Core/NDI/       NDI abstraction, discovery & routing (NDIManager), receivers
  Core/Util/      Shared helpers
  Features/
    Sources/      Discovered-source browser
    MultiView/    Grid multi-view + per-tile video rendering (deliverable #3)
    Tally/        Tally state + visual borders (deliverable #4)
    PTZ/          PTZ controller + joystick/slider UI (deliverable #4)
    KVM/          KVM trackpad + keyboard input (deliverable #4)
    AutoAngle/    Vision-based subject tracking → PTZ (deliverable #5)
  Models/         Shared value types
```

NDI® is a registered trademark of Vizrt NDI AB.
