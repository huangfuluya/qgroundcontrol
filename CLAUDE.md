# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

QGroundControl (QGC) is an open-source Ground Control Station for MAVLink-enabled UAVs, supporting PX4 and ArduPilot flight stacks. Qt6/C++20/QML application, dual-licensed Apache 2.0 and GPL.

## Build Commands

```bash
# Configure and build (Qt 6.8.3 required, Ninja generator)
qt-cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Debug
cmake --build build --config Debug

# Or use the helper script
./build_and_run_qgc.sh --build-type Debug
./build_and_run_qgc.sh --clean  # Clean build

# qt-cmake is typically at: ~/Qt/6.8.3/gcc_64/bin/qt-cmake
# Ensure Qt 6.8.3 is installed via Qt installer or aqtinstall
```

## Testing

Tests run through the QGC binary itself (not separate executables). `QGC_BUILD_TESTING` is auto-enabled for Debug builds.

```bash
# Run all tests (requires xvfb on headless Linux)
xvfb-run -a ./build/QGroundControl --unittest

# Run a single test by name
./build/QGroundControl --unittest:MissionControllerTest

# Via CTest
cd build && ctest --output-on-failure

# Stress test (runs each test 20 times)
./build/QGroundControl --unittest-stress
```

Test source lives in `test/`. Tests are registered in `test/UnitTestList.cc` via `UT_REGISTER_TEST(ClassName)`. MockLink (`src/Comms/MockLink/`) provides simulated vehicle connections for testing without hardware.

## CMake Build Options

Key options in `cmake/CustomOptions.cmake`:
- `QGC_BUILD_TESTING` — auto ON for Debug
- `QGC_VIEWER3D` — 3D viewer (requires Qt Quick3D)
- `QGC_ENABLE_BLUETOOTH`, `QGC_ENABLE_GST_VIDEOSTREAMING`, `QGC_ENABLE_QT_VIDEOSTREAMING`
- `QGC_DISABLE_APM_PLUGIN`, `QGC_DISABLE_PX4_PLUGIN` — disable firmware plugins
- `QGC_CUSTOM_BUILD` — auto-enabled when `custom/` directory exists at root

## Architecture

### Entry Point and Core

- `src/main.cc` → creates `QGCApplication` (extends `QApplication`), parses `--unittest`, `--simple-boot-test`, `--system-id`
- `src/QGCApplication.h` — core app class, manages QML engine, translations, settings. Use `qgcApp()` macro for global access.
- Each `src/` subdirectory is a self-contained CMake module producing a static library + QML module via `qt_add_qml_module()`.

### Plugin Architecture (Firmware & Autopilot)

The firmware/autopilot layer abstracts differences between flight stacks:

- `src/FirmwarePlugin/FirmwarePlugin.h` — abstract base. `FirmwarePluginManager` returns the right plugin for a `MAV_AUTOPILOT` type.
- `src/FirmwarePlugin/APM/` — per-vehicle-type plugins: `ArduCopterFirmwarePlugin`, `ArduPlaneFirmwarePlugin`, `ArduRoverFirmwarePlugin`, `ArduSubFirmwarePlugin`, plus `APMFirmwarePluginFactory`.
- `src/FirmwarePlugin/PX4/` — `PX4FirmwarePlugin` + `PX4FirmwarePluginFactory`.
- `src/AutoPilotPlugins/` — `AutoPilotPlugin` base with `VehicleComponent` abstraction. APM and PX4 implementations each provide setup components (airframe, radio, sensors, safety, power, flight modes, tuning).

### Vehicle

`src/Vehicle/Vehicle.h` — the central class (~171KB), represents a connected drone with all state. Contains `MultiVehicleManager`, `InitialConnectStateMachine`, `FTPManager`, `MAVLinkLogManager`, `RemoteIDManager`, `VehicleLinkManager`.

### Fact System (Parameters)

`src/FactSystem/` — `Fact`, `FactGroup`, `FactMetaData`, `ParameterManager`. Vehicle parameters are wrapped in `Fact` objects with metadata (type, range, enum values) and directly bindable in QML. `ParameterManager` handles the MAVLink parameter protocol.

### Communication

`src/Comms/` — `LinkManager`, `LinkInterface`, `LinkConfiguration`. Implementations: Serial, UDP, TCP, Bluetooth, MockLink, LogReplayLink, AirLink. Also contains `MAVLinkProtocol`.

### Settings Framework

`src/Settings/` — JSON-defined setting groups (`.SettingsGroup.json` files) auto-generate C++ setting classes. Managed by `SettingsManager`. Examples: `AppSettings`, `VideoSettings`, `FlightMapSettings`.

### QML/C++ Split

- **C++ backend**: exposes data via `Q_PROPERTY` and methods via `Q_INVOKABLE` to QML.
- **QML frontend**: all UI in QML, using QGC custom controls (`QGCButton`, `QGCTextField`, etc.), not raw Qt Quick Controls.
- **Global QML object**: `QGroundControlQmlGlobal` (`src/QmlControls/QGroundControlQmlGlobal.h`) exposes core managers (LinkManager, MultiVehicleManager, SettingsManager, VideoManager, etc.) to QML.
- **QML module URIs**: `QGroundControl`, `QGroundControl.Controls`, `QGroundControl.FactSystem`, `QGroundControl.FlightDisplay`, `QGroundControl.FlightMap`, `QGroundControl.Vehicle`, etc.

### Key UI Files

- `src/UI/MainWindow.qml` — top-level window
- `src/FlightDisplay/FlyView.qml` — fly view with video, guided actions, checklists
- `src/FlightDisplay/GuidedActionsController.qml` — guided action logic (go-to, RTL, land, etc.)
- `src/FlightMap/` — map components and widgets
- `src/QmlControls/` — largest QML module, reusable controls and plan editor

### Custom Builds

Place a `custom/` directory at root to override app name, resources, firmware plugins, and autopilot plugins. `custom-example/` demonstrates the pattern with custom `QGCCorePlugin`, `FirmwarePlugin`, and `AutoPilotPlugin`.

## Coding Style

**C++** (`.clang-format`): Google-based, 120 columns, 4-space indent. PascalCase classes, camelCase methods/vars, `_` prefix for private members. `Q_DECLARE_LOGGING_CATEGORY(ClassNameLog)` per class. `#pragma once` for include guards.

**QML** (`src/QmlControls/CodingStyle.qml`):
- All sizing via `ScreenTools.defaultFontPixelHeight/Width` (no hardcoded pixels)
- All colors from `QGCPalette` (no hardcoded colors)
- Use QGC custom controls, not raw Qt Quick Controls
- `_` prefix for private properties
- Public properties first, private second

## Android Build

### Prerequisites

```bash
# Qt 6.8.3 with Android toolchain (via aqtinstall)
aqt install-qt linux android 6.8.3 android_arm64_v8a \
  -m qtcharts qtlocation qtmultimedia qtpositioning qtsensors \
     qtserialport qtconnectivity qtquick3d qt5compat qtspeech \
  --outputdir ~/Qt

# Host Qt (required for cross-compile tools)
aqt install-qt linux desktop 6.8.3 gcc_64 --outputdir ~/Qt

# Android SDK/NDK
ANDROID_HOME=~/android-sdk
ANDROID_NDK=~/android-sdk/ndk/26.1.10909125
```

### Build Script: `build-android.sh`

```bash
./build-android.sh                          # Default arm64-v8a RelWithDebInfo
./build-android.sh -a x86_64 -t Release     # x86_64 Release
./build-android.sh --clean --package        # Clean rebuild + APK
./build-android.sh --herelink               # Herelink device (Qt 6.6.3)
```

**Key CMake options set by the script:**

| Option | Value | Reason |
|--------|-------|--------|
| `QGC_ENABLE_GST_VIDEOSTREAMING` | OFF | GStreamer has no Android prebuilt toolchain |
| `QGC_ENABLE_QT_VIDEOSTREAMING` | ON | Enables RTSP/UDP/TCP video via Qt6 `QMediaPlayer` |
| `QGC_CPM_SOURCE_CACHE` | `build/cpm_cache` | Shared CPM cache for mavlink, openssl, etc. |
| `ANDROID_NDK_ROOT` | env variable | Required by Qt toolchain to locate NDK cmake file |

**Critical environment variables** (set in `setup_environment()`):
- `ANDROID_NDK_ROOT` — Qt toolchain reads this to chainload `android.toolchain.cmake`
- `ANDROID_SDK_ROOT` — Qt toolchain fallback SDK path

### Video Backend (RTSP on Android)

QGC has three video backends, selected at compile time:

```
createVideoReceiver():
  #ifdef QGC_GST_STREAMING     → GStreamer (desktop default, unavailable on Android)
  #elifdef QGC_QT_STREAMING    → Qt6 QMediaPlayer (used on Android, enabled by script)
  #else                        → null (no video at all)
```

`QtMultimediaReceiver` wraps `QMediaPlayer` and handles RTSP/UDP/TCP natively. Android Qt6 ships with `ffmpegmediaplugin` + `androidmediaplugin` for hardware-accelerated decoding.

### APK Signing for Test Install

The script produces an **unsigned** APK. For test install via adb, rebuild with Gradle:

```bash
cd build/android-arm64-v8a-RelWithDebInfo/android-build
../../../../../android/gradlew assembleDebug
adb install build/outputs/apk/debug/android-build-debug.apk
```

### CPM Cache Pitfall

During CMake configure, `FetchContent` clones mavlink from GitHub. If interrupted, the cache dir at `build/cpm_cache/mavlink/<hash>/` may be empty (`.git` dir exists but no working tree), causing `mavlink_types.h: No such file or directory`. Solution: clean cache and reconfigure, or pre-clone manually into the cache.

## CI

Workflows in `.github/workflows/`. Linux CI: install Qt via `jurplel/install-qt-action@v4`, configure with `qt-cmake`, build, run tests with `xvfb-run -a ./QGroundControl --unittest`. Covers Linux, Windows, macOS, Android, iOS, Flatpak, Docker.
