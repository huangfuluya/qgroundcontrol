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
