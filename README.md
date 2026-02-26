# DynamicScrollDirection 

## Background

With Mac OS X Lion, Apple introduced the concept of "natural scrolling", in which the direction of the scroll gesture drives the direction of the on-screen scroll. I think this makes sense for trackpads (as it enhances the feeling of direct manipulation) but it still seems completely backwards when using a scroll wheel on a mouse. Ideally, I'd like my trackpad to scroll "naturally" and my mouse to scroll "traditionally". Unfortunately, while there are separate preferences for both Mouse and Trackpad scroll directions in the System Preferences app, they both map to the same `com.apple.swipescrolldirection` setting under the hood so it's impossible to have separate preferences.

**DynamicScrollDirection** essentially hacks around this limitation. It listens for mouse connection/disconnection events and sets the scroll direction appropriately -- traditional scrolling when a mouse is attached and natural scrolling when it is removed.

## Build

Compile with `clang` (no full Xcode install required — just Command Line Tools):

```bash
clang -framework Foundation -framework IOKit -framework CoreGraphics \
  -o ~/bin/DynamicScrollDirection DynamicScrollDirection/main.m
```

## Installation

1. Copy the launchd plist to `~/Library/LaunchAgents/`:

   ```bash
   cp com.snosrap.DynamicScrollDirection.plist ~/Library/LaunchAgents/
   ```

2. Update the `Program` path in the plist to match where you placed the binary (default is `~/bin/DynamicScrollDirection` — note that launchd requires the full expanded path, e.g. `/Users/yourname/bin/DynamicScrollDirection`).

3. Load the launch agent:

   ```bash
   launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.snosrap.DynamicScrollDirection.plist
   ```

   To unload later: `launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.snosrap.DynamicScrollDirection.plist`

## Alternatives

If you'd prefer a GUI, check out [Scroll Reverser](https://pilotmoon.com/scrollreverser/), which is also [open source](https://github.com/pilotmoon/Scroll-Reverser).
