# QGroundControl 项目笔记 (CLAUDE.md)

## 项目概述

QGroundControl (QGC) - 开源无人机地面控制站，支持 MAVLink 协议。

- **构建系统**: CMake ≥ 3.25 + Ninja / C++20 / Qt 6.8.3
- **源码路径**: `/home/huangluya/code/github/qgroundcontrol`
- **sudo 密码**: `huangluya`

## 新增文件

### `build-windows-cross.sh`
在 Ubuntu 上交叉编译 Windows x64 版 QGC 的一键脚本。

```bash
./build-windows-cross.sh -h                          # 帮助
./build-windows-cross.sh --install-deps               # 安装依赖
./build-windows-cross.sh --make-zip                   # 编译 + 打包 ZIP
./build-windows-cross.sh --install-deps --make-zip     # 完整流程
```

**流程**: `parse_args → install_deps → dl_qt → fix_src → cmake_cfg → do_build → do_inst → do_zip`

**关键机制**:
- `cmake_cfg`: 先 `rm -rf ${BUILD_DIR}` 避免缓存污染；**不设 CMAKE_RC_COMPILER**（会触发 cmake 重配置丢失 PREFIX_PATH）
- `do_build`: 预编译 RC + `sed` 注释 build.ninja 中 RC 规则 + `sed` 添加 `-lssp`
- `fix_src`: 修复 timespec 和 RC icon；末尾 `true` 防 `set -e` 退出
- `install_deps`: apt 命令 `|| true` 容忍网络超时
- `do_zip`: 优先从 Qt 目录复制 MinGW DLL（版本匹配）；创建 `qt.conf`；单独补充 libssp

### `cmake/toolchains/mingw-w64-x86_64.cmake`
- `CMAKE_FIND_ROOT_PATH_MODE_*` = `BOTH`（否则 Qt find_package 失败）
- 编译器: `x86_64-w64-mingw32-g++-posix`
- `-static-libgcc -static-libstdc++`

## 交叉编译 Bug 总览

| # | 问题 | 根因 | 修复 |
|---|------|------|------|
| 1 | MAVLink tag 404 | GitHub remote 无此 commit | `-DQGC_CPM_SOURCE_CACHE` |
| 2 | `timespec` 重定义 | `_MSC_VER` 未定义时 MinGW 冲突 | `defined(_MSC_VER) &&` |
| 3 | `windres: no resources` | ninja 大批 `-I` 干扰 windres | sed 注释 RC 规则 |
| 4 | `__stack_chk_fail` 链接 | 需 `libssp` 但未链接 | sed 添加 `-lssp` |
| 5 | CMake 重配置失 Qt | `CMAKE_RC_COMPILER` 变触发缓存清理 | 不设此变量 |
| 6 | 脚本闪退 | `grep -q && {...}` + `set -e` | `if grep; then fi` + 末尾 `true` |
| 7 | apt 网络超时 | teamviewer 源不可达 | `|| true` + 重试 |
| 8 | `unbound variable` | 编辑器损坏 heredoc | 手动重写 do_zip |

## Windows 部署 DLL 问题

| # | 问题 | 根因 | 修复 |
|---|------|------|------|
| 1 | `Qt6MultimediaQuick.dll` 缺失 | cmake install 只部署 exe+QML，不复制 Qt 主 DLL | do_zip 复制 60+ Qt DLL |
| 2 | `__glibcxx_assert_fail` 入口点 | Qt(GCC13) vs 系统(GCC10) libstdc++ 不匹配 | 用 Qt 自带 libstdc++ (2.2MB) |
| 3 | `libssp-0.dll` 缺失 | `-lssp` 链接需要，Qt 不捆绑 | 从系统 MinGW 单独复制 |
| 4 | 点击无反应 | 缺 `qt.conf` + 可能需要命令行看日志 | 添加 qt.conf |

## MinGW 运行时 DLL 来源

| DLL | 来源 | 原因 |
|-----|------|------|
| `libstdc++-6.dll` | `TG_QT/bin/` | Qt 用 GCC13，版本必须匹配 |
| `libgcc_s_seh-1.dll` | `TG_QT/bin/` | 同上 |
| `libwinpthread-1.dll` | `TG_QT/bin/` | 同上 |
| `libssp-0.dll` | `/usr/lib/gcc/.../10-posix/` | Qt 不捆绑，GCC10 兼容 |

## Qt 安装

| 路径 | 用途 |
|------|------|
| `~/Qt/6.8.3/gcc_64` | Linux 主机工具 (moc/uic) |
| `~/Qt-windows/6.8.3/mingw_64` | Windows MinGW 目标库 |

```bash
python3 -m aqt install-qt linux desktop 6.8.3 gcc_64 -O ~/Qt -m ${QT_MODS}
python3 -m aqt install-qt windows desktop 6.8.3 win64_mingw -O ~/Qt-windows -m ${QT_MODS}
# 注意: -m 后面的模块列表不能加引号
```

## 已知限制

- **GStreamer 视频**: 禁用 (MSVC DLL 与 MinGW ABI 不兼容)
- **Bluetooth / UVC**: 交叉编译禁用
- **NSIS 安装器**: Linux 无法生成，改 ZIP

## 产物结构

```
build/windows-cross/
├── Release/QGroundControl.exe                    ← 编译产物 (50MB)
├── QGroundControl-windows-x64-Release.zip        ← 部署包 (64MB)
│   └── QGroundControl-portable/
│       ├── QGroundControl.exe
│       ├── qt.conf                               ← Qt 插件路径配置
│       ├── Qt6*.dll × 60+
│       ├── libstdc++-6.dll                       ← Qt 自带 GCC13
│       ├── libgcc_s_seh-1.dll / libwinpthread-1.dll
│       ├── libssp-0.dll                          ← 系统 GCC10
│       ├── platforms/qwindows.dll
│       ├── qml/ (QML 模块)
│       └── imageformats/, sqldrivers/, ... (Qt 插件)
├── staging/                                      ← cmake --install 输出
└── cpm_modules/                                  ← CPM 包缓存
```

## 修复的源文件

- `src/GPS/definitions.h`: timespec `#if (_MSC_VER)` → `#if defined(_MSC_VER) &&`
- `deploy/windows/QGroundControl.rc`: icon 路径 `./WindowsQGC.ico` → `deploy/windows/WindowsQGC.ico`
- `src/AutoPilotPlugins/Common/RadioComponentController.cc`: `RC_TYPE_SPEKTRUM_DSM2`/`RC_TYPE_SPEKTRUM_DSMX` → `RC_TYPE_SPEKTRUM` (新版 MAVLink 合并了这两个常量)

---

## Windows 原生编译 (2026-07-04)

### `build-windows.ps1`

Windows 原生一键编译+部署脚本，支持 PowerShell 5.1+。

```powershell
.\build-windows.ps1                        # Release 编译+部署
.\build-windows.ps1 -CleanBuild -Force     # 清理后重建(非交互)
.\build-windows.ps1 -Package               # 编译+打包 NSIS 安装器
.\build-windows.ps1 -BuildType Debug       # Debug 构建
.\build-windows.ps1 -Jobs 8                # 指定并行数
.\build-windows.ps1 -QtPath "D:\Qt\6.8.3\msvc2022_64"  # 手动指定 Qt 路径
```

**6 步流程**: `检测环境 → 验证 MSVC → CMake 配置 → 编译 → 部署运行时 → (可选)打包`

### 环境检测

- **VS 2022**: `vswhere.exe` → 手动搜索常见路径
- **Ninja**: 优先 VS 内置 (`Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja\`)，验证 PATH 中版本可用性（排除损坏的 WinGet 版本）
- **CMake**: PATH 查找 ≥ 3.25
- **Qt 6.8.3**: `$QtPath` 参数 → `QT_ROOT_DIR` 环境变量 → `CMAKE_PREFIX_PATH` → 常见路径搜索 → `C:\Qt` 递归扫描
- **GStreamer 1.22.12**: 环境变量 → 常见路径；未找到仅警告不阻断
- **Git + GitHub 连通性**: `[System.Net.WebRequest]` 超时 10s 测试，检查代理配置

### MSVC 环境

通过临时 `.bat` 文件封装 `vcvars64.bat` + `cmake`，确保编译器环境变量正确传递。所有 cmake 调用都走此封装。

### CMake 配置

- 生成器: `Ninja Multi-Config` (Ninja 可用时) / `Visual Studio 17 2022` (回退)
- Toolchain: `qt.toolchain.cmake`
- 参数: `-DQGC_STABLE_BUILD=OFF -DQGC_BUILD_TESTING=OFF`
- GStreamer 检测: 自动传递 `-DGSTREAMER_ROOT`；未找到由脚本提示安装

### 运行时部署 (Step 5)

| 步骤 | 工具/操作 | 部署内容 |
|------|----------|---------|
| Qt 部署 | `windeployqt --release --qmldir src` | 55 个 Qt6 DLL + QML 模块 + 18 个插件目录 + 翻译文件 |
| GStreamer 部署 | 全量复制 `bin/*.dll` | 所有运行时 DLL (186+) |
| GStreamer 插件 | 复制 `lib/gstreamer-1.0/*.dll` | 236 个插件到 `gstreamer-1.0/` 子目录 |

### 环境准备

**GStreamer 安装** (需要管理员权限):
```powershell
.\tools\setup\install-dependencies-windows.ps1
```
或手动下载安装:
- `gstreamer-1.0-msvc-x86_64-1.22.12.msi`
- `gstreamer-1.0-devel-msvc-x86_64-1.22.12.msi`
来源: `https://gstreamer.freedesktop.org/data/pkg/windows/1.22.12/msvc/`

**Git 代理配置** (如果直连 GitHub 失败):
```powershell
git config --global http.proxy http://127.0.0.1:7897
git config --global https.proxy http://127.0.0.1:7897
```

### 产物结构

```
build/qt6-Windows/
├── Release/
│   ├── QGroundControl.exe              ← 38.83 MB (appDir)
│   ├── Qt6*.dll × 55+                  ← windeployqt 部署
│   ├── gst*.dll, glib*.dll, ...        ← GStreamer 运行时 DLL (bin/*.dll)
│   ├── D3Dcompiler_47.dll, opengl32sw.dll
│   ├── platforms/qwindows.dll
│   ├── qml/ (QML 模块)
│   ├── translations/ (*.qm)
│   └── imageformats/, sqldrivers/, ... (Qt 插件)
├── lib/                                ← ../lib from appDir
│   ├── gstreamer-1.0/ (236 plugins)    ← QGC 硬编码路径
│   └── gio/modules/
├── libexec/                            ← ../libexec from appDir
│   └── gstreamer-1.0/ (gst-plugin-scanner)
├── Debug/
├── cpm_modules/                        ← CPM 包缓存
└── build-Release.ninja
```

**重要**: QGC 的 `_setGstEnvVars()` 在 Windows 上硬编码了 `../lib/gstreamer-1.0/` 和 `../libexec/` 路径（相对于 exe 所在目录）。因此 GStreamer 插件必须放在 `$BuildDir/lib/` 层级，不能放在 `$BuildDir/Release/` 内。

### RTSP 视频流

QGC 使用 `rtspsrc` 元素（来自 `gst-plugins-good`）处理 RTSP。确保以下 GStreamer 插件已部署：
- `gstrtsp.dll`, `gstrtspclientsink.dll` (RTSP 协议)
- `gstrtp.dll`, `gstrtpmanager.dll`, `gstrtpmanagerbad.dll`, `gstrtponvif.dll` (RTP 传输)
- `gstsrtp.dll`, `gstrsrtp.dll` (SRTP 加密)

### RTSP 视频流卡顿修复 (2026-07-04, 第二轮修复 2026-07-31)

**问题**: QGC 查看 RTSP 视频流时画面卡顿，但 VLC 拉同一路流非常流畅。

**第一轮修复 (2026-07-04)** — 发现 10 个问题，覆盖网络缓冲层、解码层、渲染层：

| # | 层面 | 文件 | 修复 |
|---|------|------|------|
| 1 | 网络 | `GstVideoReceiver.cc` | `rtspsrc latency`: 25ms → 低延迟50ms/正常200ms |
| 2 | 网络 | `GstVideoReceiver.cc` | 低延迟模式也创建 `rtpjitterbuffer`（最少50ms） |
| 3 | 网络 | `GstVideoReceiver.cc` | `rtspsrc` 增加 `drop-on-latency=TRUE`, `do-retransmission=TRUE` |
| 4 | 网络 | `GstVideoReceiver.cc` | `rtpjitterbuffer` 配置 `latency=_buffer`, `do-retransmission=TRUE` |
| 5 | 解码 | `GstVideoReceiver.cc` | 解码队列: max-buffers=60, max-time=2s, leaky=2 |
| 6 | 解码 | `GstVideoReceiver.cc` | 录制队列: max-buffers=30, max-time=500ms, leaky=2 |
| 7 | 解码 | `GstVideoReceiver.cc` | `decodebin3.low-latency=TRUE` 启用 |
| 8 | 解码 | `GstVideoReceiver.cc` | qml6glsink `processing-deadline=33ms` (≈30fps) |
| 9 | 渲染 | `gstqml6glsink.cc` | GL buffer pool: 2→4 最小缓冲 |
| 10 | 渲染 | `qt6glitem.cc` | 移除 `updatePaintNode` 每帧 `setCaps` 冗余调用 |

**第二轮修复 (2026-07-31)** — 第一轮后仍卡顿，根本原因是 `rtspsrc.latency` 值过小（80ms vs VLC 默认 ~1000ms），导致网络抖动缓冲完全失效：

#### 核心问题：rtspsrc 网络缓冲配置错误

`rtspsrc.latency` 控制内部 jitter buffer 大小。GStreamer 默认 2000ms，VLC 使用 ~1000ms。
第一轮修复后该值仍为 80ms（低延迟模式），仅为 GStreamer 默认值的 4%，VLC 的 8%。

后果链：
> `latency=80ms` + `drop-on-latency=TRUE` → 任何超过 80ms 到达的数据包被直接丢弃 → WiFi/蜂窝网络正常抖动 50-200ms → 大量丢帧 → 卡顿

第二轮修复（共 5 项，均在 `GstVideoReceiver.cc`）：

| # | 问题 | 原值 | 修复后 | 效果 |
|---|------|------|--------|------|
| 1 | `rtspsrc.latency` 过小 | `_buffer` (80ms) | 低延迟 300ms / 正常 500ms | 网络缓冲扩大 3.75-6.25× |
| 2 | `drop-on-latency=TRUE` 过于激进 | TRUE | **FALSE** | 不再因缓冲满而主动丢包 |
| 3 | RTSP 传输协议自动选 UDP | 默认(UDP优先) | `protocols=0x04` (TCP only) | 消除无线 UDP 丢包(5-15%) |
| 4 | `videoSink.sync=TRUE` 导致时钟丢帧 | `(_buffer>=0)` = TRUE | **FALSE** | 帧到达即渲染，不等待时钟 |
| 5 | `decodebin3.low-latency=TRUE` 跳过B帧 | TRUE → FALSE | **FALSE** (恢复全解码) | 恢复完整 30fps |
| 6 | `processing-deadline` 33ms 过于激进 | `GST_SECOND/30` (33ms) | 低延迟40ms / 正常66ms | 解码+渲染时间宽裕 |
| 7 | 解码队列 `leaky=2` 丢最旧帧 | leaky=2, 60buf, 32MB | **leaky=1**, 90buf, 64MB | 保护关键帧，防止解码器重同步 |
| 8 | `QMetaObject::invokeMethod("update")` 帧积压 | 每帧无脑入队 | `update_pending` 标志合并 | 防止主线程事件队列淹没 |
| 9 | GL 缓冲池偏小 | 4 最小 | **6** 最小 | Qt Scene Graph 持有 2-3 帧时管线不阻塞 |
| 10 | 未启用 QoS | 无 | `gst_base_sink_set_qos_enabled(TRUE)` | 智能跳帧替代累积延迟 |

#### 修改文件清单（两轮合计）

```
src/VideoManager/VideoReceiver/GStreamer/GstVideoReceiver.cc           (第二轮+67)
src/VideoManager/VideoReceiver/GStreamer/gstqml6gl/qt6/gstqml6glsink.cc (+3/-2)
src/VideoManager/VideoReceiver/GStreamer/gstqml6gl/qt6/qt6glitem.cc     (+16/-2)
```

#### 关键设计原则

- **网络缓冲 ≠ 显示缓冲**：`rtspsrc.latency` 处理网络抖动（需要数百 ms），不应与显示队列共享同一个 80ms 值
- **TCP > UDP**：无线链路上 TCP interleaved 的可靠性远优于 UDP 丢包重传
- **sync=FALSE**：实时视频不需要时钟同步，帧到达即渲染
- **全帧解码**：B 帧带来的 ~33ms 延迟远小于恢复 30fps 流畅度的收益

---

## 基本模式 UI 定制 (2026-07-04)

以下为针对无人船场景对 `src/UI/BasicMode/BasicFlyView.qml` 的定制修改：

### 底部快捷模式按钮

| 按钮 | 变更 | 飞行模式值 |
|------|------|-----------|
| 手动模式 | 保留 | `"Manual"` |
| 悬停模式 → **抛锚模式** | 改名 | `"Loiter"` |
| ~~保持模式~~ | **已删除** | `"Hold"` |
| 自动模式 | 保留 | `"Auto"` |

容器宽度从 `×62` 调整为 `×50`（适配 3 按钮布局）。

### 左侧状态栏：电量 → 电压

- **文件**: `FlyViewVideo.qml` 第 96-111 行
- **标签**: `"电量"` → `"电压"`
- **数据源**: `_activeVehicle.batteryPercent`（不存在，始终 `"--"`）→ `_activeVehicle.batteries.get(0).voltage`（从飞控 `BATTERY_STATUS` 消息获取）
- **显示格式**: `16.8V`（`voltage.valueString + voltage.units` 自动格式化）
- **颜色**: 有 `percentRemaining` 时按百分比变色，否则绿色

### 视频切换按钮

- **文件**: `FlyViewVideo.qml` 第 96-111 行
- `"CH1"/"CH2"` 动态切换 → 固定 `"摄像头切换"`
- 按钮宽度 `×6` → `×14`（适配 5 字中文）

### 航点规划按钮重构 (2026-07-04)

**文件**: `src/UI/BasicMode/BasicPlanView.qml`

将五个按钮中的"开始任务"和"暂停任务"重构为"上传航点"和"下载航点"：

| 原按钮 | 新按钮 | 功能 | 启用条件 |
|--------|--------|------|---------|
| ~~开始任务~~（绿色） | **上传航点**（绿色） | 确认后调用 `planMasterController.sendToVehicle()` | 活跃车辆 + 航点数 > 1 |
| ~~暂停任务~~（橙色） | **下载航点**（橙色） | 调用 `planMasterController.loadFromVehicle()`，下载后自动显示 | 活跃车辆 |

**同步变更**：
- 删除 `_missionRunning` 属性（不再追踪任务执行状态）
- 删除底部 `missionProgressBar`（任务进度条）
- 删除 `PlanMasterController.upload()` 自定义方法
- "添加/删除/清空"按钮移除 `!_missionRunning` 启用限制
- 新增 `confirmUploadDialog` 上传确认对话框

### 清空任务修复 (2026-07-04)

**问题**: 基本模式下点击"清空任务"按钮后，地图上的航点没有被清除。

**根因**: `MissionController::removeAll()` 替换了 `_visualItems` 为新模型，但未发出 `visualItemsChanged()` 信号，导致 QML `Repeater` 仍持有旧模型引用。

**修复文件**:
- `src/MissionManager/MissionController.cc`: `removeAll()` 末尾添加 `emit visualItemsChanged()`
- `src/UI/BasicMode/BasicPlanView.qml`: 确认回调中增加 `planMasterController.removeAllFromVehicle()`，同步清除飞控上的任务

### 日志下载界面修复 (2026-07-04)

**文件**: `src/UI/BasicMode/BasicLogDownloadView.qml`

1. **状态反馈**: 新增 `_statusMessage` + 10 秒超时 `Timer` + 500ms 轮询检测
   - 未连接: "请先连接飞控"
   - 请求中: "正在请求日志列表…"
   - 超时: "飞控未响应，可能不支持日志下载"
2. **复选框修复**: `Binding on checkState` → `checked: object.selected`（避免内部状态冲突导致灰色不可选）
3. **列表文字颜色**: 外层 `Rectangle` 的 `opacity: 0.05` 级联影响子元素 → 拆分为独立背景 `Rectangle` + 内容 `Item`
4. **黑屏修复**: 移除 `on_prevModelCountChanged`（QML 下划线属性命名不兼容）→ 改用轮询 `Timer`

### 删除紧急停船按钮 (2026-07-04)

**文件**: `src/UI/BasicMode/BasicFlyView.qml`

从右侧快捷操作按钮栏中删除了"紧急停船"按钮：

- 删除 `btnStop` Rectangle 及内部的 `QGCButton`（原来位于 RTL 和锁定按钮之间）
- 删除 `confirmStopDialog` MessageDialog 确认对话框
- 将"锁定/解锁"按钮（`btnArm`）的锚点从 `btnStop.bottom` 改为 `btnRTL.bottom`，保持布局连续

### 水深数据源切换：RANGEFINDER → DISTANCE_SENSOR (2026-07-31)

**背景**：简单模式左侧状态栏"水深"显示的数据来源于 `MAVLINK_MSG_ID_RANGEFINDER`（#173，ArduPilot 专有方言），需要改为解析标准 mavlink 消息 `MAVLINK_MSG_ID_DISTANCE_SENSOR`（#132）。

**数据流**：
```
飞控 → DISTANCE_SENSOR (#132) → current_distance (cm) ÷ 100 → rangeFinderDist Fact (m) → QML 显示 "水深: X.Xm"
```

**修改文件**：

| 文件 | 改动 |
|------|------|
| `src/Vehicle/FactGroups/VehicleFactGroup.h` 第 87 行 | 新增 `_handleDistanceSensor` 方法声明 |
| `src/Vehicle/FactGroups/VehicleFactGroup.cc` 第 74-76 行 | 新增 `MAVLINK_MSG_ID_DISTANCE_SENSOR` 路由 |
| `src/Vehicle/FactGroups/VehicleFactGroup.cc` 第 217-225 行 | 新增处理函数：解码 → cm→m 转换 → 写入 `rangeFinderDist` |

**关键设计决策**：
- 复用同一个 Fact（`_rangeFinderDistFact`），**QML 层零改动**
- `current_distance` 单位厘米，需 `/100.0` 转为米
- DISTANCE_SENSOR 在 RANGEFINDER 之前路由，但两者互不冲突（不同 msgid）
- 保留 RANGEFINDER 处理作为回退（`#ifndef QGC_NO_ARDUPILOT_DIALECT` 保护）
- 不判断传感器 `orientation`（只有单路水深传感器）

### 一键返航按钮行为分析 (2026-07-04)

**文件**: `src/UI/BasicMode/BasicFlyView.qml` + C++ 固件插件

点击"一键返航"按钮的完整调用链：

| 步骤 | 位置 | 动作 |
|------|------|------|
| ① UI 确认 | `BasicFlyView.qml:460` | 弹出确认对话框 `confirmRTLDialog` |
| ② 调用 Vehicle | `Vehicle.cc:2088` | `Vehicle::guidedModeRTL(false)` 检查引导模式支持 |
| ③ 固件分发 | `APMFirmwarePlugin.cc:844` / `PX4FirmwarePlugin.cc:309` | APM → `RTL` 模式，PX4 → `AUTO_RTL` 模式 |
| ④ 模式切换+验证 | `FirmwarePlugin.cc:263` | `_setFlightModeAndValidate` 发送 MAVLink `SET_MODE` 命令，最多重试3次，每次等待1.3秒 |
| ⑤ 飞控执行 | 飞控固件 | 自主导航返回 home 点 |

---

## 遥测 MAVLink CSV 日志修复 (2026-08-01)

**背景**: 基础模式"日志下载"页右侧遥测日志面板实时记录 MAVLink 消息到 CSV。需求：记录所有收到的 MAVLink 消息，且所有字段可解码、十进制记录。

### 问题 1：部分消息被漏记

原实现挂在 `Vehicle::mavlinkMessageReceived` 信号上，该信号在 `Vehicle::_mavlinkMessageReceived` **末尾**才 emit，中途提前 `return` 的消息不会被记录：

| 提前 return 位置 | 漏记的消息 |
|------------------|-----------|
| sysid 过滤 (`sysid != _id && sysid != 0`) | 其他系统 ID 消息（RADIO_STATUS 除外，属有意过滤） |
| `TerrainProtocolHandler::mavlinkMessageReceived` return false | **TERRAIN_REQUEST (133)、TERRAIN_REPORT (136)** |
| `_firmwarePlugin->adjustIncomingMavlinkMessage` return false | 被固件插件吞掉的消息（当前版本未触发，存在风险） |
| `QGCCorePlugin::mavlinkMessage` return false | 被核心插件吞掉的消息（默认 return true） |

**修复**: 移除构造函数中 `connect(this, &Vehicle::mavlinkMessageReceived, ...)`，改为在 `_mavlinkMessageReceived` 内 sysid 过滤之后、其他所有过滤之前直接调用 `_logMavlinkMessage(message)`。

### 问题 2：非硬编码消息只记 ID，payload 全丢

原实现仅硬编码解码 8 种消息（HEARTBEAT/SYS_STATUS/GPS_RAW_INT/SCALED_PRESSURE/ATTITUDE/GLOBAL_POSITION_INT/VFR_HUD/BATTERY_STATUS），其余消息走 default 只记 `ID_xxx`。

**修复**: 改用 MAVLink 方言消息信息表 `mavlink_get_message_info()` 通用解码（`MAVLINK_USE_MESSAGE_INFO` 已在 `src/MAVLink/MAVLinkLib.h` 定义；编译的 `all` 方言包含 ardupilotmega/common/development 全部消息，二分查找）：

- 所有字段按 `字段名=值` **十进制**输出（float 9 位有效数字、double 17 位，保证精度不丢）
- 数组字段按下标展开：`voltages[0]=12600;voltages[1]=12601;...`
- char 数组按引号字符串记录：`text="ArduPilot Ready"`
- 方言表之外的未知消息按字节**十进制**记录：`byte0=12;byte1=34;...`
- 新增文件级静态辅助函数 `_mavlinkWireLength()` / `_mavlinkFieldValueToString()`（memcpy 按线序偏移安全解码，避免未对齐访问 UB）

### CSV 格式变化

```
旧: Timestamp,MsgID,MsgName,SysID,CompID,Field1,Field2,...,Field8   (固定8列，字段数>8的消息放不下)
新: Timestamp,MsgID,MsgName,SysID,CompID,Data                       (Data 列为 ; 分隔的 name=value 对)
```

示例行：
```
2026-08-01 16:40:17.123,30,ATTITUDE,1,1,time_boot_ms=12345;roll=-0.0123;pitch=0.0345;yaw=1.5708;...
```

**注意**: Excel 打开后 Data 列在单个单元格内，需"数据→分列→分号分隔"拆分，或用 pandas 按 `;` 拆分。

### 修改文件

| 文件 | 改动 |
|------|------|
| `src/Vehicle/Vehicle.cc` | 记录点前移至 `_mavlinkMessageReceived` 入口；`_logMavlinkMessage` 重写为查表通用解码 |
| `src/UI/BasicMode/BasicLogDownloadView.qml` | 右侧面板说明文字更新为新 CSV 格式 |

### 架构说明

- Vehicle 创建之前（连接后第一个心跳到达前）的消息无法记录，属 per-vehicle 日志的固有限制
- 每条消息实时 `flush()` 写盘，~100-200Hz 遥测下主线程有 IO 压力，目前可接受；如需优化可改缓冲批量写入
- 左侧板载日志下载（LogDownloadController）与本次改动无关

---

## 网络 RTK (NTRIP) 差分注入 (2026-08-01)

**背景**: 原代码仅支持本地串口 RTK 基站（GPSProvider → RTCMMavlink → 飞控），`src/GPS/NTRIP/` 目录为空，无网络差分功能。本次实现完整 NTRIP 客户端，将 caster 的 RTCM 数据经 MAVLink `GPS_RTCM_DATA` 注入飞控。

### 架构

```
NTRIP caster (TCP) → NtripTcpClient (握手/RTCM3解析/CRC24Q校验/白名单过滤)
                   → NTRIPManager (重连/GGA上报/状态)
                   → RTCMMavlink → GPS_RTCM_DATA → 所有已连接车辆
```

全程 GUI 线程异步（QTcpSocket 非阻塞），未引入额外线程。

### 新增文件

| 文件 | 说明 |
|------|------|
| `src/GPS/NTRIP/NtripTcpClient.cc/h` | NTRIP v1(`ICY 200 OK`)/v2(HTTP) 握手、Basic 鉴权、RTCM3 帧解析 + CRC24Q 表驱动校验、消息 ID 白名单、GGA 发送；挂载点留空走原始 RTCM-over-TCP |
| `src/GPS/NTRIP/NTRIPManager.cc/h` | 断线 5s 重连、每 10s 上报 GGA（优先飞行器坐标，回退 QGCPositionManager）、暴露 `ntripStatus`/`connected` 给 QML |
| `src/Settings/NTRIPSettings.cc/h` + `NTRIP.SettingsGroup.json` | 7 个配置项：开关/地址/端口/用户名/密码/挂载点/白名单；设置修改即时生效自动重连，无需重启 |
| `src/UI/AppSettings/NTRIPSettings.qml` | 设置页，含实时状态（绿=已连接/橙=连接中/红=错误） |

### 修改文件

| 文件 | 改动 |
|------|------|
| `SettingsManager.cc/h` | 注册 `ntripSettings` 组（QML 经 `QGroundControl.settingsManager.ntripSettings` 访问） |
| `GPSManager.cc/h` | 持有 `NTRIPManager`（GPSManager 为 Q_APPLICATION_STATIC，首次 instance() 时创建，晚于 SettingsManager::init，时序安全） |
| `QGroundControlQmlGlobal.cc/h` | 暴露 `QGroundControl.ntripManager`（`#ifndef QGC_NO_SERIAL_LINK` 保护） |
| `SettingsPagesModel.qml` | 新增 "NTRIP/RTK" 页入口 |
| `src/GPS/CMakeLists.txt` | 加入 NTRIP 源文件 + `Qt6::Network` + NTRIP 头文件路径 |
| `src/Settings/CMakeLists.txt`、`src/UI/AppSettings/CMakeLists.txt`、`qgroundcontrol.qrc` | 构建/资源注册 |

### 关键实现要点

- **CRC24Q 表驱动**：与 PX4-GPSDrivers 位运算实现经 1000 组随机数据验证完全等价
- **RTCM 帧解析**：0xD3 前导 + 10bit 长度 + CRC24Q 校验，校验失败逐字节重同步，防无限循环
- **GGA 格式**：`$GPGGA,hhmmss.ss,ddmm.mmmm,N/S,dddmm.mmmm,E/W,1,12,0.8,alt,M,0.0,M,,*CS`（VRS 挂载点必需）
- **错误后必重连**：`_onSocketError` 中检测 socket 已 Unconnected 时主动补发 `disconnected()`（Qt 某些错误路径不再发该信号）
- **`_onSocketConnected` 状态守卫**：防止连接中途用户停止后迟到的 connected 信号误发握手
- 注意：**本地串口 RTK 基站与 NTRIP 不要同时使用**，两路 RTCM 会同时注入飞控

### 本仓库与上游差异备忘

- 本版本 FactMetaData JSON 键名为 `shortDesc`/`longDesc`/`default`（上游新版为 `shortDescription`/`defaultValue`）
- 上游 master 的 NTRIP 实现为 22 文件复杂架构（2026-02 重写），本实现为精简版（4 文件），未含 SPARTN/Source Table 浏览器/UDP 转发


