# CLAUDE.md

## Project overview

macOS command-line utility (Objective-C) that runs as a launch agent. Two features:
1. **Scroll direction** — switches to traditional scrolling when a USB mouse is attached, natural scrolling when removed
2. **Litra light** — toggles Logitech Litra light on/off when any camera is activated/deactivated

Single source file: `Periphery/main.m`

## Build

```bash
xcodebuild -configuration Release
```

Binary output: `build/Release/Periphery`

Alternatively, build with clang directly (add `-framework CoreMediaIO` for camera monitoring):
```bash
clang -framework Foundation -framework IOKit -framework CoreGraphics -framework CoreMediaIO \
  -o ~/bin/Periphery Periphery/main.m
```

## Deploy

```bash
cp build/Release/Periphery ~/bin/Periphery
launchctl unload ~/Library/LaunchAgents/com.tariqrafique.Periphery.plist
launchctl load ~/Library/LaunchAgents/com.tariqrafique.Periphery.plist
```

## Key technical details

- **Frameworks**: IOKit HID (mouse monitoring + Litra control), CoreMediaIO (camera monitoring), CoreGraphics (scroll direction)
- **Litra HID protocol**: Vendor `0x046d`, usage page `0xff43`. On/off via 20-byte output report `[0x11, 0xff, prefix, 0x1c, 0x01/0x00, ...]` where prefix is `0x04` (Glow/Beam) or `0x06` (Beam LX). Protocol derived from [litra-rs](https://github.com/timrogers/litra-rs).
- **Camera monitoring**: Uses `kCMIODevicePropertyDeviceIsRunningSomewhere` property listeners. On any camera state change, all monitored cameras are polled — some camera apps pre-open multiple cameras at launch, so individual callbacks can't be relied on alone.
- **CLANG_ENABLE_MODULES=YES** in the Xcode project, so `#import` auto-links frameworks without manual pbxproj edits
- `CGSSetSwipeScrollDirection` is an undocumented CoreGraphics API

## Debugging

```bash
/usr/bin/log show --predicate 'process == "Periphery"' --last 5m | grep -E "Camera state|Litra|Monitoring|Attached|Removed"
```
