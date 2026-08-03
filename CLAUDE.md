@AGENTS.md

# 相机变倍（Zoom）功能强制开启 — 修改记录

## 需求

QGC 视频界面（FlyView）默认不显示相机变倍控件，需要为支持 zoom 的数字相机强制开启该功能。

## 问题诊断

1. 变倍控件由 `_camera.hasZoom` 控制显示：
   - 右上角 `PhotoVideoControl.qml` 的 Zoom 垂直滑块（`visible: _camera.hasZoom`）
   - 视频画面 `FlightDisplayViewVideo.qml` 的 `PinchArea` 捏合缩放（`enabled: _hasZoom`）
2. 相机控制器有两种：
   - `VehicleCameraControl`：真实 MAVLink 相机，仅在收到相机器件 HEARTBEAT 且响应 `CAMERA_INFORMATION` 后创建（`QGCCameraManager.cc:164/176/321`）。`hasZoom()` 依赖相机上报的 `CAMERA_CAP_FLAGS_HAS_BASIC_ZOOM` 标志。
   - `SimulatedCameraControl`：通用占位控制器。相机未完成上述协议流程时 QGC 回退使用。`hasZoom()` 硬编码 false，`stepZoom`/`setZoomLevel` 为空实现。
3. 本机相机实际走 `SimulatedCameraControl`（未完成 CAMERA_INFORMATION 流程）。判断依据：界面有 Camera Tracking 按钮（`hasTracking` 强制 true）但无 Zoom 滑块（`hasZoom` false）。

## 修改内容

### `src/Camera/VehicleCameraControl.h`（第 80 行）
- `hasZoom()` 由读取 `CAMERA_CAP_FLAGS_HAS_BASIC_ZOOM` 标志改为强制 `return true`（覆盖真实 MAVLink 相机路径）。

### `src/Camera/SimulatedCameraControl.h`
- `hasZoom()` 强制 `return true`。
- `zoomLevel()` 返回新增的 `_zoomLevel` 成员（原硬编码 1.0）。
- `stepZoom`/`startZoom`/`stopZoom`/`setZoomLevel` 由内联空实现改为声明。
- 新增成员 `qreal _zoomLevel = 0.0`。

### `src/Camera/SimulatedCameraControl.cc`
- 实现 4 个 zoom 方法，参照已有的 tracking 定制模式，通过 `_vehicle->sendMavCommand(_vehicle->defaultComponentId(), ...)` 发送 `MAV_CMD_SET_CAMERA_ZOOM`：
  - `setZoomLevel` → `ZOOM_TYPE_RANGE`（0-100，滑块拖动）
  - `stepZoom` → `ZOOM_TYPE_STEP`（±1）
  - `startZoom`/`stopZoom` → `ZOOM_TYPE_CONTINUOUS`（direction / 0）
  - 同时更新 `_zoomLevel` 并 emit `zoomLevelChanged`。

## 关键坑点

- **`showError` 必须为 `false`**：zoom 滑块 `live: true`，拖动时高频连续触发命令。`MavCommandQueue` 对同一 command 去重（前一个未响应则丢弃新的），若 `showError=true` 会反复弹出 "Unable to send command: Waiting on previous response to same command."。zoom 命令必须像 `VehicleCameraControl` 一样用 `showError=false`，让高频重复命令静默丢弃。
- 命令目标组件为 `_vehicle->defaultComponentId()`（飞控默认组件），与已有 tracking 一致。

## 验证

- 右上角相机面板出现 Zoom 垂直滑块，拖动不再弹警告，相机可实际变倍。
- 桌面端用滑块变倍；视频画面 PinchArea 捏合缩放需触摸屏。

## 构建

- 增量构建：`python build_qgc.py build`（Windows；需先关闭运行中的 QGC，否则链接报 `LNK1168 无法打开 QGroundControl.exe 进行写入`）。
- 若 ninja 未检测到头文件改动（提示 "no work to do"），需 touch 对应 `.cc` 触发重编。

---

# 构建与分发工具链 — 2026-08-03

## 背景

直接双击 `build/Debug/QGroundControl.exe` 报错：Qt 程序依赖大量 DLL、QML 模块、平台插件和 GStreamer 运行时，这些不在 exe 同级目录。需通过 CMake install + windeployqt 收集所有依赖生成自包含的分发目录。

## 修改内容

### `build_qgc.py` — 新增 `deploy` 动作

在已有 `configure/build/run/rebuild/clean/all` 的基础上新增 `deploy` 动作：

- 默认使用 **Release** 配置 + **`build_release`** 目录（可通过 `BUILD_TYPE`/`BUILD_DIR` 环境变量覆盖）。
- 自动串联三步：`configure` → `build` → `cmake --install`。
- `cmake --install` 阶段自动调用 `windeployqt` 收集所有 Qt/QML/GStreamer/MSVC DLL 到 `staging/` 目录。
- 完成后输出 staging 路径、DLL 数量、以及拷贝到另一台电脑的操作指引。

**用法**：
```batch
python build_qgc.py deploy
# 或
build_qgc.bat deploy
# 自定义：set BUILD_DIR=build_my_release && set JOBS=16 && python build_qgc.py deploy
```

### `build_qgc.bat` — 用法注释更新

新增 `deploy` 动作说明。

### `cmake/find-modules/FindGStreamer.cmake` — GStreamer pkg-config quiet 修复

第 224–229 行：`pkg_check_modules` 调用缺少 `QUIET` 参数，导致非必需 GStreamer 插件缺失时打印大量警告。修复为：必需组件用 `REQUIRED`，非必需组件用 `QUIET`。

### `src/Utilities/Platform/Platform.cc` — Qt 6.11+ Debug 控制台崩溃修复

第 194–200 行：Qt 6.11 的 `initDebuggingConsole()` 在 GUI 子系统进程无继承控制台时，`freopen_s` 返回的 `FILE*` 与 MSVC CRT 的 `stdin` 不一致，触发 `Q_ASSERT(in == stdin)` 崩溃。注释掉自动 `QT_WIN_DEBUG_CONSOLE=attach`，让用户手动设置。

## 分发流程

1. `build_qgc.bat deploy` 生成 `build_release\staging\`
2. 将整个 `staging` 目录拷贝到目标电脑
3. 在目标电脑上安装 VC++ Redist：`staging\bin\vc_redist.x64.exe`
4. 双击 `staging\bin\QGroundControl.exe` 即可运行
5. 如需生成 NSIS 安装包，需安装 NSIS 并确保 `makensis.exe` 在 PATH 中
