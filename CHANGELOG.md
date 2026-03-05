# Changelog

## 2026-03-05

### Fixed: Camera re-discovery on disconnect/reconnect

In clamshell mode (and USB replug / dock-undock scenarios), cameras get new CoreMediaIO device IDs when they reconnect. Previously, `SetupCameraMonitoring()` only enumerated cameras once at startup, so the monitored list went stale and the Litra light stopped toggling.

Added a system-level `kCMIOHardwarePropertyDevices` property listener that fires whenever cameras appear or disappear. On each change, `RefreshCameraMonitoring()` tears down old per-camera listeners, re-enumerates all devices, registers fresh listeners, and polls current state. This ensures the Litra light works reliably across camera reconnections.

## 2025-12-16

### Added: Poll all cameras on state change

Fixed missed camera events during camera switching by polling all monitored cameras whenever any single camera state change fires. Some camera apps pre-open multiple cameras at launch, so individual callbacks can't be relied on alone.

## 2025-12-15

### Added: Litra light control via camera monitoring

Toggle Logitech Litra light on/off when any camera is activated/deactivated, using CoreMediaIO property listeners and IOKit HID output reports.

### Renamed: DynamicScrollDirection to Periphery

Renamed the project to reflect its broader scope (scroll direction + Litra light control).
