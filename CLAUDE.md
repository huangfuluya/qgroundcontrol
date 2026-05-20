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

## CI

Workflows in `.github/workflows/`. Linux CI: install Qt via `jurplel/install-qt-action@v4`, configure with `qt-cmake`, build, run tests with `xvfb-run -a ./QGroundControl --unittest`. Covers Linux, Windows, macOS, Android, iOS, Flatpak, Docker.
