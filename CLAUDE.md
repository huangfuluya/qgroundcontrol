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

### App Icon

App icons are generated from `resources/zhuangzhou.png` (1467×1467 RGBA). To update the logo, resize this source image to all required formats:

| Target | Size | Location |
|--------|------|----------|
| Android ldpi | 36×36 | `android/res/drawable-ldpi/icon.png` |
| Android mdpi | 48×48 | `android/res/drawable-mdpi/icon.png` |
| Android hdpi | 72×72 | `android/res/drawable-hdpi/icon.png` |
| Android xhdpi | 96×96 | `android/res/drawable-xhdpi/icon.png` |
| Android xxhdpi | 144×144 | `android/res/drawable-xxhdpi/icon.png` |
| Android xxxhdpi | 192×192 | `android/res/drawable-xxxhdpi/icon.png` |
| Main icon | 512×512 | `resources/icons/qgroundcontrol.png` |
| Android 512 | 512×512 | `resources/icons/android_512x512.png` |
| Windows ICO | 16/32/48/64/128/256 | `deploy/windows/WindowsQGC.ico` |
| Splash screen | 626×145 | `resources/SplashScreen.png` |

### Session Change Summary (2026-07-01)

Three commits on branch `zhuangzhouv508`:

| Commit | Description |
|--------|-------------|
| `324a09f17` | Add `build-android.sh` — Android build script with NDK fix, RTSP video, CPM cache. Update `CLAUDE.md`. |
| `601ac50a1` | Replace all app icons with `zhuangzhou.png`. |

**Environment setup performed:**
- Installed missing Qt Android modules via aqt: `qtcharts`, `qtlocation`, `qtmultimedia`, `qtpositioning`, `qtsensors`, `qtserialport`, `qtconnectivity`, `qtquick3d`, `qt5compat`, `qtspeech`
- Pre-populated CPM cache at `build/cpm_cache/` with mavlink `c_library_v2`

**Verified:** CMake configure passes (10s with cache), APK builds and installs on Redmi Note 12 5G (Android 14).
Desktop build requires isolated pkg-config due to conda GStreamer path interference.

### Session Change Summary (2026-07-03) — 双路视频切换功能

在 `zhuangzhouv508` 分支上实现双路 RTSP 视频流同时接收、单路切换显示功能。

**需求描述：**
- 同时接收两路 RTSP 视频流（两台独立的 GStreamer VideoReceiver 并行解码）
- 同一时间只显示一路视频，通过 Fly View 右上角 CH1/CH2 按钮切换
- 基本模式和高级模式都支持

**架构改动：**

```
┌─ Settings ─────────────────────────────────────────┐
│ Video.SettingsGroup.json: +8 第二路配置项          │
│ VideoSettings.h/cc: +9 Fact, streamConfigured2()   │
└────────────────────────────────────────────────────┘
                        ↓
┌─ VideoManager ─────────────────────────────────────┐
│ init(): 三路 receiver — "videoContent",            │
│         "thermalVideo", "secondVideoContent"       │
│ _updateSettings(): secondVideoContent 分支独立     │
│   使用 videoSource2/rtspUrl2/udpUrl2 等配置        │
│ _secondVideoSourceChanged(): 第二路独立启停        │
│ _startReceiver(): 第二路使用正确的 videoSource2    │
│ +8 Q_PROPERTY: hasVideo2, decoding2, streaming2... │
│ +8 NOTIFY signals: hasVideo2Changed, ...           │
│ +2 成员: _decoding2, _streaming2                   │
└────────────────────────────────────────────────────┘
                        ↓
┌─ QML UI ───────────────────────────────────────────┐
│ FlyViewVideo.qml:                                  │
│   property bool _showingSecondVideo (toggle state) │
│   FlightDisplayViewVideo: visible=!_showingSecond  │
│   QGCVideoBackground "secondVideoContent":         │
│     visible=_showingSecond                         │
│   QGCButton CH1/CH2: visible=hasVideo2             │
│                                                    │
│ FlyView.qml / BasicFlyView.qml:                    │
│   PipView item2: (hasVideo||hasVideo2) ?           │
│     videoControl : null                            │
│                                                    │
│ VideoSettings.qml: +4 SettingsGroupLayout          │
│   (第二路来源/连接/参数配置UI)                      │
└────────────────────────────────────────────────────┘
```

**修改文件清单（10个文件+1次UI调整）：**

| # | 文件 | 改动 |
|---|---|---|
| 1 | `src/Settings/Video.SettingsGroup.json` | +8 第二路配置项：streamEnabled2, videoSource2, udpUrl2, rtspUrl2, tcpUrl2, aspectRatio2, disableWhenDisarmed2, lowLatencyMode2 |
| 2 | `src/Settings/VideoSettings.h` | +9 DEFINE_SETTINGFACT + streamConfigured2() + streamConfigured2Changed 信号 |
| 3 | `src/Settings/VideoSettings.cc` | +6 NO_FUNC 实现 + streamConfigured2() + videoSource2 enum 初始化 + _configChanged 增强 |
| 4 | `src/VideoManager/VideoManager.h` | +8 Q_PROPERTY + 8 信号 + _secondVideoSourceChanged 槽 + _decoding2/_streaming2 成员 |
| 5 | `src/VideoManager/VideoManager.cc` | init() 增加 "secondVideoContent" receiver；_updateSettings() 第二路分支使用 videoSource2 配置；_startReceiver() 第二路区分；_videoSourceChanged() 跳过第二路；_secondVideoSourceChanged() 独立管理第二路 |
| 6 | `src/FlightDisplay/FlyViewVideo.qml` | +_showingSecondVideo 状态 + 第二路 QGCVideoBackground 叠加层 + CH1/CH2 切换按钮 |
| 7 | `src/FlightDisplay/FlyView.qml` | PipView 条件从 hasVideo → (hasVideo\|\|hasVideo2) |
| 8 | `src/UI/AppSettings/VideoSettings.qml` | +4 个 SettingsGroupLayout（Second Video Stream/Source/Connection/Settings） |
| 9 | `src/UI/BasicMode/BasicFlyView.qml` | PipView: (hasVideo\|\|hasVideo2)；底部按钮: 悬停→抛锚, 删除保持模式(3按钮) |
| 10 | `src/UI/BasicMode/BasicVideoView.qml` | 完整重写：移植 FlightDisplayViewVideo 视频渲染 + OnScreenGimbalController 云台控制 + MouseArea 跟踪ROI + CH1/CH2 切换 |

**使用方式：**
1. Settings → General → Video → 勾选 "Enable Second Video Stream"
2. 选择第二路视频源（如 RTSP），填入 URL
3. Fly View 右上角出现 CH1/CH2 按钮，点击切换显示

**编译：** `cmake --build build --target QGroundControl` 通过（Debug, gcc, Qt 6.8.3）

### Session Change Summary (2026-07-03 #2) — 基本模式云台/相机控制按钮面板

在 `zhuangzhouv508` 分支上，于基本模式的航行监控界面（BasicFlyView.qml）添加 3×2 云台控制按钮面板 + 圆形回中按钮，并修改视频切换按钮文字。

**需求描述：**
- 6 个 PWM 伺服控制按钮（拍照/录像/变焦远/变焦近/夜视/补光），布局为 3 行 × 2 列
- 脉冲型按钮（拍照/录像/变焦）发送 PWM 后自动延时复位到 1500
- 切换型按钮（夜视/补光）在 PWM 最大值/最小值之间交替
- 1 个圆形回中按钮，使用 MAV_CMD_DO_MOUNT_CONTROL 指令
- 视频切换按钮 CH1/CH2 → "摄像头切换"

**架构：**

```
┌─ BasicFlyView.qml 新增组件 ─────────────────────────────────────┐
│                                                                  │
│  ┌─ leftStrip ─────┐  ┌─ servoPanel (3×2 GridLayout) ──────┐   │
│  │ 模式/航速/航向   │  │ ┌─────────┬─────────┐              │   │
│  │ 电量/水深/解锁   │  │ │ 拍照    │ 录像    │  ← CH10     │   │
│  │                  │  │ │ 2000→1s │ 1000→1s │    脉冲+确认 │   │
│  │                  │  │ ├─────────┼─────────┤              │   │
│  │                  │  │ │ 变焦远  │ 变焦近  │  ← CH9      │   │
│  │                  │  │ │ 1000→.5s│ 2000→.5s│    无确认    │   │
│  │                  │  │ ├─────────┼─────────┤              │   │
│  │                  │  │ │ 夜视    │ 补光    │  ← CH11/12  │   │
│  │                  │  │ │ 切换    │ 切换    │    保持      │   │
│  │                  │  │ └─────────┴─────────┘              │   │
│  │                  │  │         ╭──────╮                   │   │
│  │                  │  │         │ 回中 │  ← MOUNT_CONTROL │   │
│  │                  │  │         ╰──────╯    (205)          │   │
│  └──────────────────┘  └────────────────────────────────────┘   │
│                                                                  │
│  Timers:                                                         │
│    zoomResetTimer  (500ms)  → 变焦通道复位 (无确认等待)           │
│    servoResetTimer (1000ms) → 拍照/录像复位 (等 MAV_RESULT=0)    │
│                                                                  │
│  Connections:                                                    │
│    onMavCommandResult → cmd==183 && result==0 → servoResetTimer  │
└──────────────────────────────────────────────────────────────────┘
```

**按钮行为详解：**

| 按钮 | 通道 | 指令 | 复位 | 确认机制 |
|------|------|------|------|----------|
| 拍照 | CH10 | PWM 2000 | 1s→1500 | 等待 MAV_RESULT_ACCEPTED |
| 录像 | CH10 | PWM 1000 | 1s→1500 | 等待 MAV_RESULT_ACCEPTED |
| 变焦远 | CH9 | PWM 1000 | 0.5s→1500 | 无需确认，直接启动定时器 |
| 变焦近 | CH9 | PWM 2000 | 0.5s→1500 | 无需确认，直接启动定时器 |
| 夜视 | CH11 | 切换 2000↔1000 | 保持 | 无 |
| 补光 | CH12 | 切换 2000↔1000 | 保持 | 无 |
| 回中 | — | MAV_CMD_DO_MOUNT_CONTROL(205), MAV_MOUNT_MODE_NEUTRAL(1) | — | 无 |

**UI 规格：**
- 面板位置：左侧状态条右侧，底部（quickModeBar 上方）
- 按钮颜色：统一 `#4A90D9`（切换按钮 off 态 `#2C5F8A`）
- 按钮透明度：`opacity: 0.5`
- 回中按钮：圆形（`radius: width/2`），尺寸 `fontPixelHeight * 5`
- 全屏视频时自动隐藏

**关键技术点：**
- PWM 指令通过 `_activeVehicle.sendCommand(compId=1, cmd=183(MAV_CMD_DO_SET_SERVO), showError=false, channel, pwm, ...)` 发送
- 脉冲按钮通过 `_servoPulseChannel` 标志位区分"设置"与"复位"命令，避免复位脉冲触发新一轮 mavCommandResult 循环
- 变焦按钮使用独立 `zoomResetTimer`（500ms）+ `_zoomPulseChannel`，与拍照/录像的 `servoResetTimer`（1000ms）完全分离
- 回中使用 `sendCommand(1, 205, false, 0, 0, 0, 0, 0, 0, 1)` — 不操作 PWM 通道

**修改文件清单：**

| # | 文件 | 改动 |
|---|---|---|
| 1 | `src/UI/BasicMode/BasicFlyView.qml` | +servoPanel（3×2 GridLayout）+centerButton（圆形回中）+zoomResetTimer+servoResetTimer+onMavCommandResult 监听；+4 状态属性 |
| 2 | `src/UI/BasicMode/BasicVideoView.qml` | CH1/CH2 按钮文字改为固定 "摄像头切换" |
| 3 | `CLAUDE.md` | 新增本段会话摘要 |

**编译：** 需要 `cmake --build build --target QGroundControl` 重新编译（QML 文件通过 `qgroundcontrol.qrc` 嵌入二进制）

## CI

Workflows in `.github/workflows/`. Linux CI: install Qt via `jurplel/install-qt-action@v4`, configure with `qt-cmake`, build, run tests with `xvfb-run -a ./QGroundControl --unittest`. Covers Linux, Windows, macOS, Android, iOS, Flatpak, Docker.
