# Integrating the real NDI SDK

The repo compiles against `MockNDIService` so it runs with **no** proprietary
binary. To drive real cameras, drop in the official SDK and flip one flag.

## 1. Obtain the SDK

Download *NDI SDK for Apple Platforms* (iOS) from the NDI website and accept the
license. You get headers (`include/Processing.NDI.Lib.h`, …) and a library
(`lib/iOS/libndi_ios.a`, or an `.xcframework`).

## 2. Add it to the Xcode project (do not commit the binary)

1. Copy the SDK into `Vendor/NDI/` (git-ignored — see `.gitignore`).
2. In the app target → *General → Frameworks, Libraries* add the `.xcframework`
   (or the static `.a` plus `-lc++` and the `Accelerate`/`VideoToolbox` system
   frameworks the SDK needs).
3. Add the headers folder to *Header Search Paths*.

## 3. Expose the C API to Swift via a module map

Create `Vendor/NDI/module.modulemap`:

```
module NDISDK {
    header "Processing.NDI.Lib.h"
    link "ndi_ios"
    export *
}
```

Add its folder to *Import Paths* (`SWIFT_INCLUDE_PATHS`). Swift can now
`import NDISDK` and call `NDIlib_initialize()`, `NDIlib_find_create_v2()`, etc.

## 4. Enable the real service

`LibNDIService.swift` is wrapped in `#if USE_REAL_NDI`. Add `USE_REAL_NDI` to the
target's *Active Compilation Conditions* (Swift flags). `AppState` then selects
`LibNDIService()` instead of `MockNDIService()` automatically.

## 5. Info.plist (local network permission)

NDI discovery uses Bonjour/mDNS, which on iOS 14+ requires:

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>Used to discover NDI video sources on your network.</string>
<key>NSBonjourServices</key>
<array>
    <string>_ndi._tcp</string>
</array>
```

## 6. Lifecycle

- Call `NDIlib_initialize()` once at launch (`LibNDIService.init`) and
  `NDIlib_destroy()` at teardown.
- `NDIlib_is_supported_CPU()` should be checked before init.
