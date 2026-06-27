#!/usr/bin/env python3
"""
Generate app icons for NDIMonitor from icons/app_icon.svg.

Requirements (macOS):
  brew install librsvg imagemagick

Requirements (Linux):
  sudo apt install librsvg2-bin imagemagick

Usage:
  python3 scripts/generate_icons.py

Outputs:
  NDIMonitor/Resources/Assets.xcassets/AppIcon.appiconset/  (macOS/iOS PNG sizes)
  WindowsApp/assets/icon.ico                                (Windows)
  WindowsApp/assets/icon.icns                               (macOS Electron/DMG)
  WindowsApp/assets/icon.png                                (1024x1024 generic)
"""

import subprocess
import os
import sys
import shutil

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SVG  = os.path.join(ROOT, "icons", "app_icon.svg")

# ----- iOS/Mac AppIcon sizes -----
IOS_MAC_SIZES = [
    16, 20, 29, 32, 40, 48, 50, 55, 57, 58, 60,
    64, 72, 76, 80, 87, 88, 100, 114, 120, 128,
    144, 152, 167, 172, 180, 196, 216, 256, 512, 1024,
]

ICON_SET_DIR = os.path.join(
    ROOT, "NDIMonitor", "Resources", "Assets.xcassets", "AppIcon.appiconset"
)
WIN_ASSETS   = os.path.join(ROOT, "WindowsApp", "assets")


def run(cmd: list[str]) -> None:
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"ERROR: {' '.join(cmd)}\n{result.stderr}", file=sys.stderr)
        sys.exit(1)


def require(tool: str) -> str:
    path = shutil.which(tool)
    if not path:
        print(f"ERROR: '{tool}' not found. Install it first.", file=sys.stderr)
        sys.exit(1)
    return path


def rsvg_convert(size: int, output: str) -> None:
    run([require("rsvg-convert"), "-w", str(size), "-h", str(size), "-o", output, SVG])


def convert_to_ico(sources: list[str], output: str) -> None:
    run([require("convert")] + sources + [output])


def convert_to_icns(png_1024: str, output: str) -> None:
    # macOS `iconutil` approach via a temporary iconset folder
    iconset = output.replace(".icns", ".iconset")
    os.makedirs(iconset, exist_ok=True)

    icns_sizes = [16, 32, 64, 128, 256, 512, 1024]
    for s in icns_sizes:
        rsvg_convert(s, os.path.join(iconset, f"icon_{s}x{s}.png"))
        if s <= 512:
            rsvg_convert(s * 2, os.path.join(iconset, f"icon_{s}x{s}@2x.png"))

    iconutil = shutil.which("iconutil")
    if iconutil:
        run([iconutil, "-c", "icns", iconset, "-o", output])
        shutil.rmtree(iconset)
        print(f"  -> {output}")
    else:
        print(f"  SKIP icns: 'iconutil' not found (macOS only). Iconset at {iconset}")


def generate_contents_json(sizes: list[int]) -> str:
    import json
    images = []
    for s in sizes:
        images.append({
            "filename": f"icon_{s}.png",
            "idiom": "universal",
            "scale": "1x",
            "size": f"{s}x{s}"
        })
    return json.dumps({"images": images, "info": {"author": "xcode", "version": 1}}, indent=2)


def main() -> None:
    if not os.path.isfile(SVG):
        print(f"ERROR: SVG not found at {SVG}", file=sys.stderr)
        sys.exit(1)

    rsvg = shutil.which("rsvg-convert")
    if not rsvg:
        print("ERROR: rsvg-convert not found. Install librsvg first.", file=sys.stderr)
        sys.exit(1)

    os.makedirs(ICON_SET_DIR, exist_ok=True)
    os.makedirs(WIN_ASSETS, exist_ok=True)

    # --- iOS/Mac PNGs ---
    print("Generating iOS/Mac icon sizes...")
    for size in IOS_MAC_SIZES:
        out = os.path.join(ICON_SET_DIR, f"icon_{size}.png")
        rsvg_convert(size, out)
        print(f"  {size}x{size} -> {out}")

    # Write Contents.json for Xcode
    contents = os.path.join(ICON_SET_DIR, "Contents.json")
    with open(contents, "w") as f:
        f.write(generate_contents_json(IOS_MAC_SIZES))
    print(f"  Contents.json -> {contents}")

    # --- Windows .ico (multiple sizes baked in) ---
    print("\nGenerating Windows .ico...")
    ico_sizes = [16, 24, 32, 48, 64, 128, 256]
    ico_pngs  = []
    for s in ico_sizes:
        p = os.path.join(WIN_ASSETS, f"_ico_{s}.png")
        rsvg_convert(s, p)
        ico_pngs.append(p)
    ico_out = os.path.join(WIN_ASSETS, "icon.ico")
    convert_to_ico(ico_pngs, ico_out)
    for p in ico_pngs:
        os.remove(p)
    print(f"  -> {ico_out}")

    # --- 1024px PNG for Electron ---
    png_out = os.path.join(WIN_ASSETS, "icon.png")
    rsvg_convert(1024, png_out)
    print(f"  -> {png_out}")

    # --- .icns for Electron Mac build ---
    print("\nGenerating macOS .icns...")
    icns_out = os.path.join(WIN_ASSETS, "icon.icns")
    convert_to_icns(png_out, icns_out)

    print("\nDone! All icons generated.")


if __name__ == "__main__":
    main()
