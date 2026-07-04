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

### RTSP 视频流卡顿修复 (2026-07-04)

**问题**: QGC 查看 RTSP 视频流时画面卡顿，但 VLC 拉同一路流非常流畅。

**根因**: 共发现 10 个问题，涵盖网络缓冲层、解码层、渲染层三个层面：

#### 网络缓冲层 (GstVideoReceiver.cc)

| # | 问题 | 原值 | 修复后 | 影响 |
|---|------|------|--------|------|
| 1 | `rtspsrc latency` 太低 | 固定 25ms | 低延迟=50ms，正常=200ms | **最大影响** — 25ms 抖动缓冲无法吸收网络抖动 |
| 2 | 低延迟模式跳过 `rtpjitterbuffer` | `_buffer = -1` 时不创建 | 总是创建，最少 50ms | 任何网络包延迟波动都直接导致卡顿 |
| 3 | `rtspsrc` 缺少丢帧/重传 | 无 | `drop-on-latency=TRUE`, `do-retransmission=TRUE` | 超时帧不等待 + RTP 丢包重传 |
| 4 | `rtpjitterbuffer` 未配置 | 创建后无属性 | `latency=_buffer`, `do-retransmission=TRUE` | jitter buffer 知道预期延迟 |

#### 解码层 (GstVideoReceiver.cc)

| # | 问题 | 原值 | 修复后 |
|---|------|------|--------|
| 5 | 解码队列无大小限制 | 未配置 | max-buffers=60(2s@30fps), max-time=2s, leaky=2 |
| 6 | 录制队列无大小限制 | 未配置 | max-buffers=30, max-time=500ms, leaky=2 |
| 7 | `decodebin3` 低延迟模式 | 未启用 | `low-latency=TRUE` (GStreamer ≥1.24) |
| 8 | 无 processing-deadline | 未设置 | qml6glsink 设置 33ms deadline (≈30fps) |

#### 渲染层

| # | 文件 | 问题 | 修复 |
|---|------|------|------|
| 9 | `gstqml6glsink.cc` | GL buffer pool 最小 2 | 增加到 4，避免 Qt Scene Graph 持帧导致的管线阻塞 |
| 10 | `qt6glitem.cc` | `updatePaintNode` 每帧调 `setCaps` | 移除冗余调用，setCaps 仅 caps 变化时需要 |

#### 尚未修复但需要注意的问题

| # | 问题 | 建议 |
|---|------|------|
| A | **QueuedConnection update() 合并** | Qt 合并排队 update()，30fps 时可能丢帧 |
| B | **Windows 可能用软解码** | 优先将 `forceVideoDecoder` 设为 `DirectX3D` |
| C | **GL fence 同步阻塞渲染线程** | `gstqsg6glnode.cc:151` `gst_gl_sync_meta_wait` 每帧阻塞 |

#### 修改文件清单

```
src/VideoManager/VideoReceiver/GStreamer/GstVideoReceiver.cc      (+67/-3)
src/VideoManager/VideoReceiver/GStreamer/gstqml6gl/qt6/gstqml6glsink.cc (+3/-2)
src/VideoManager/VideoReceiver/GStreamer/gstqml6gl/qt6/qt6glitem.cc     (+3/-1)
```

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


