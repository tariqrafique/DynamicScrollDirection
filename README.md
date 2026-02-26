# DynamicScrollDirection

A lightweight macOS utility that runs as a launch agent and does two things:

1. **Dynamic scroll direction** — automatically switches to traditional scrolling when a USB mouse is connected, and back to natural scrolling when it's removed.

2. **Litra light control** — automatically turns on a Logitech Litra light when any camera becomes active (e.g. joining a video call) and turns it off when all cameras stop.

## How it works

### Scroll direction

macOS has separate Mouse and Trackpad scroll direction settings in System Preferences, but they both map to the same `com.apple.swipescrolldirection` preference — so it's impossible to have natural scrolling on the trackpad and traditional scrolling with a mouse at the same time. This utility listens for USB mouse connect/disconnect events via IOKit HID and toggles the setting automatically.

### Litra light

Uses CoreMediaIO to monitor `kCMIODevicePropertyDeviceIsRunningSomewhere` across all camera devices. When any camera state changes, all monitored cameras are polled to determine if at least one is active. The Litra light is controlled directly via IOKit HID output reports — no external CLI tools required. Supports Litra Glow, Litra Beam, and Litra Beam LX.

## Build

```bash
xcodebuild -configuration Release
```

Or compile directly with `clang` (only Command Line Tools required):

```bash
clang -framework Foundation -framework IOKit -framework CoreGraphics -framework CoreMediaIO \
  -o ~/bin/DynamicScrollDirection DynamicScrollDirection/main.m
```

## Installation

1. Copy the launchd plist to `~/Library/LaunchAgents/`:

   ```bash
   cp com.snosrap.DynamicScrollDirection.plist ~/Library/LaunchAgents/
   ```

2. Update the `Program` path in the plist to match where you placed the binary (default is `~/bin/DynamicScrollDirection` — launchd requires the full expanded path, e.g. `/Users/yourname/bin/DynamicScrollDirection`).

3. Load the launch agent:

   ```bash
   launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.snosrap.DynamicScrollDirection.plist
   ```

   To unload later: `launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.snosrap.DynamicScrollDirection.plist`

## Alternatives

If you'd prefer a GUI for scroll direction, check out [Scroll Reverser](https://pilotmoon.com/scrollreverser/), which is also [open source](https://github.com/pilotmoon/Scroll-Reverser).

## Acknowledgements

- Original scroll direction utility by [Ford Parsons (snosrap)](https://github.com/snosrap)
- Litra HID protocol derived from [litra-rs](https://github.com/timrogers/litra-rs) by Tim Rogers
