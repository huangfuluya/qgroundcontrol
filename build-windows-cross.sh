#!/usr/bin/env bash
# QGC Windows x64 Cross-Compile Script
set -euo pipefail

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; N='\033[0m'
info()    { echo -e "${B}[INFO]${N}  $*" >&2; }
ok()      { echo -e "${G}[OK]${N}    $*" >&2; }
warn()    { echo -e "${Y}[WARN]${N}  $*" >&2; }
die()     { echo -e "${R}[ERROR]${N} $*" >&2; exit 1; }

ROOT="$(cd "$(dirname "$0")" && pwd)"
QT_VER="${QT_VERSION:-6.8.3}"
HOST_QT="${HOST_QT_DIR:-${HOME}/Qt/${QT_VER}/gcc_64}"
TG_QT="${TARGET_QT_DIR:-${HOME}/Qt-windows/${QT_VER}/mingw_64}"
QT_MODS="qtcharts qtlocation qtpositioning qtspeech qt5compat qtmultimedia qtserialport qtimageformats qtshadertools qtconnectivity qtquick3d qtsensors"
CPM_CACHE="${HOME}/code/github/qgroundcontrol/build/cpm_modules"

BTYPE="Release"; JOBS=""; DO_DEPS=0; DO_CLEAN=0; SKIP_CFG=0; DO_ZIP=0

usage() {
cat <<'HELP'
用法: ./build-windows-cross.sh [选项]

选项:
  -t, --build-type TYPE    Debug|Release|RelWithDebInfo (默认: Release)
  -j, --jobs N             并行任务数
  --qt-version VER          Qt版本 (默认: 6.8.3)
  --host-qt-dir PATH        Linux Qt目录
  --target-qt-dir PATH      Windows MinGW Qt目录
  --install-deps            安装依赖 (mingw-w64 + aqtinstall)
  --clean                   清理后重新编译
  --skip-configure          跳过CMake配置
  --make-zip                打包ZIP
  -h, --help                本帮助

示例:
  ./build-windows-cross.sh --install-deps --make-zip
  ./build-windows-cross.sh -t Release -j 8 --make-zip

输出: build/windows-cross/Release/QGroundControl.exe
HELP
}

parse() {
    while [[ $# -gt 0 ]]; do case "$1" in
        -t|--build-type)  BTYPE="$2"; shift 2 ;;
        -j|--jobs)        JOBS="$2"; shift 2 ;;
        --qt-version)     QT_VER="$2"; HOST_QT="${HOME}/Qt/${QT_VER}/gcc_64"; TG_QT="${HOME}/Qt-windows/${QT_VER}/mingw_64"; shift 2 ;;
        --host-qt-dir)    HOST_QT="$2"; shift 2 ;;
        --target-qt-dir)  TG_QT="$2"; shift 2 ;;
        --install-deps)   DO_DEPS=1; shift ;;
        --clean)          DO_CLEAN=1; shift ;;
        --skip-configure) SKIP_CFG=1; shift ;;
        --make-zip)       DO_ZIP=1; shift ;;
        -h|--help)        usage; exit 0 ;;
        *) die "未知选项: $1";;
    esac; done
}

install_deps() {
    info "安装交叉编译工具..."
    echo huangluya | sudo -S apt-get update -y -q 2>/dev/null || true
    echo huangluya | sudo -S apt-get install -y -q mingw-w64 g++-mingw-w64-x86-64-posix gcc-mingw-w64-x86-64-posix ninja-build 2>/dev/null || true
    if ! command -v x86_64-w64-mingw32-g++-posix >/dev/null 2>&1; then
        echo huangluya | sudo -S apt-get install -y mingw-w64 g++-mingw-w64-x86-64-posix gcc-mingw-w64-x86-64-posix ninja-build
    fi
    python3 -c "import aqt" 2>/dev/null || python3 -m pip install -q --user aqtinstall
    for c in x86_64-w64-mingw32-g++-posix ninja; do command -v "$c" >/dev/null || die "缺少 $c"; done
    ok "依赖安装完成"
}

dl_qt() {
    [[ -d "${HOST_QT}/bin" ]] || { info "下载 Linux Qt..."; mkdir -p "$(dirname "${HOST_QT}")"
        python3 -m aqt install-qt linux desktop "${QT_VER}" gcc_64 -O "$(dirname "${HOST_QT}")" -m ${QT_MODS}; }
    [[ -d "${TG_QT}/bin" ]] || { info "下载 Windows MinGW Qt..."; mkdir -p "$(dirname "${TG_QT}")"
        python3 -m aqt install-qt windows desktop "${QT_VER}" win64_mingw -O "$(dirname "${TG_QT}")" -m ${QT_MODS}; }
}

fix_src() {
    local f="${ROOT}/src/GPS/definitions.h"
    if grep -q '#if (_MSC_VER < 1900)' "$f" 2>/dev/null; then
        sed -i 's|#if (_MSC_VER < 1900)|#if defined(_MSC_VER) \&\& (_MSC_VER < 1900)|' "$f"; info "Fixed timespec"
    fi
    local rc="${ROOT}/deploy/windows/QGroundControl.rc"
    if grep -q '"./WindowsQGC.ico"' "$rc" 2>/dev/null; then
        cp "$rc" "${rc}.orig"; printf 'IDI_ICON1 ICON "deploy/windows/WindowsQGC.ico"\r\n' > "$rc"; info "Fixed RC icon"
    fi
    true
}

cmake_cfg() {
    info "CMake 配置..."
    rm -rf "${BUILD_DIR}"; mkdir -p "${BUILD_DIR}"
    local tf="${ROOT}/cmake/toolchains/mingw-w64-x86_64.cmake"
    cmake -S "${ROOT}" -B "${BUILD_DIR}" -G Ninja \
        "-DCMAKE_TOOLCHAIN_FILE=${tf}" \
        "-DQT_HOST_PATH=${HOST_QT}" \
        "-DCMAKE_PREFIX_PATH=${TG_QT}" \
        "-DCMAKE_BUILD_TYPE=${BTYPE}" \
        "-DCMAKE_INSTALL_PREFIX=${BUILD_DIR}/staging" \
        -DQGC_STABLE_BUILD=OFF -DQGC_BUILD_TESTING=OFF -DQGC_VIEWER3D=ON \
        -DQGC_ENABLE_GST_VIDEOSTREAMING=OFF -DQGC_ENABLE_QT_VIDEOSTREAMING=ON \
        -DQGC_ENABLE_BLUETOOTH=OFF -DQGC_ENABLE_UVC=OFF \
        "-DQGC_CPM_SOURCE_CACHE=${CPM_CACHE}" \
        || die "CMake 配置失败"
    ok "CMake 配置完成"
}

do_build() {
    info "编译中 (约30-60分钟)..."
    cd "${BUILD_DIR}"
    cp "${ROOT}/deploy/windows/WindowsQGC.ico" WindowsQGC.ico 2>/dev/null || true
    cp "${ROOT}/deploy/windows/WindowsQGC.ico" deploy/windows/WindowsQGC.ico 2>/dev/null || true

    # 预编译RC & 注释掉ninja中的RC规则
    /usr/bin/x86_64-w64-mingw32-windres -O coff -I . deploy/windows/QGroundControl.rc \
        CMakeFiles/QGroundControl.dir/deploy/windows/QGroundControl.rc.res 2>/dev/null || \
        { mkdir -p "$(dirname CMakeFiles/QGroundControl.dir/deploy/windows/QGroundControl.rc.res)"
          touch CMakeFiles/QGroundControl.dir/deploy/windows/QGroundControl.rc.res; }
    sed -i '/build.*QGroundControl.rc.res: RC_COMPILER/,/^$/s/^/#/' build.ninja 2>/dev/null || true

    # 添加 -lssp
    sed -i 's| -lshell32 | -lssp -lshell32 |' build.ninja 2>/dev/null || true

    ninja -k 0 all || die "编译失败"
    cd "${ROOT}"
    [[ -f "${BUILD_DIR}/Release/QGroundControl.exe" ]] || die "未生成exe"
    ok "编译完成"
}

do_inst() {
    info "安装..."
    cd "${BUILD_DIR}"
    local d="${BUILD_DIR}/.dmy/makensis"; mkdir -p "$(dirname "$d")"
    printf '#!/bin/bash\nfor a; do case "$a" in *OutFile*) touch "${a#*OutFile }";; esac; done\nexit 0\n' > "$d"
    chmod +x "$d"
    PATH="$(dirname "$d"):${PATH}" cmake --install . --config "${BTYPE}" 2>/dev/null || warn "install 有警告(NSIS相关可忽略)"
    cd "${ROOT}"
}

do_zip() {
    local exe="${BUILD_DIR}/Release/QGroundControl.exe"; [[ -f "$exe" ]] || die "无exe"
    local p="${BUILD_DIR}/_pkg/QGroundControl"; rm -rf "$p"; mkdir -p "$p"; cp "$exe" "$p/"
    info "Copying Qt DLLs..."
    for dll in Qt6Core Qt6Gui Qt6Widgets Qt6Qml Qt6Quick Qt6QuickControls2 \
               Qt6QuickControls2Impl Qt6QuickTemplates2 Qt6QuickLayouts \
               Qt6QuickWidgets Qt6Network Qt6Sql Qt6Xml Qt6Svg \
               Qt6Charts Qt6ChartsQml Qt6Location Qt6Positioning Qt6PositioningQuick \
               Qt6Multimedia Qt6MultimediaQuick Qt6Sensors Qt6SensorsQuick \
               Qt6SerialPort Qt6OpenGL Qt6OpenGLWidgets Qt6Core5Compat \
               Qt6TextToSpeech Qt6Concurrent Qt6Quick3D Qt6Quick3DRuntimeRender \
               Qt6Quick3DUtils Qt6ShaderTools Qt6QmlMeta Qt6QmlModels Qt6QmlWorkerScript \
               Qt6QuickShapes Qt6QuickDialogs2 Qt6QuickDialogs2QuickImpl Qt6QuickDialogs2Utils \
               Qt6LabsAnimation Qt6LabsFolderListModel Qt6LabsQmlModels Qt6QuickEffects \
               Qt6QmlCore Qt6QmlLocalStorage Qt6QmlXmlListModel Qt6DBus Qt6PrintSupport; do
        [[ -f "${TG_QT}/bin/${dll}.dll" ]] && cp "${TG_QT}/bin/${dll}.dll" "$p/"; done
    info "Copying Qt plugins..."
    for pl in platforms imageformats styles sqldrivers multimedia tls iconengines networkaccess position genericsensors; do
        [[ -d "${TG_QT}/plugins/${pl}" ]] && { mkdir -p "$p/$pl"; cp -rn "${TG_QT}/plugins/${pl}/"* "$p/$pl/" 2>/dev/null || true; }; done
    info "Copying QML modules..."
    if [[ -d "${TG_QT}/qml" ]]; then mkdir -p "$p/qml"
        for m in QtCore QtQml QtQmlMeta QtQmlModels QtQmlWorkerScript QtQmlXmlListModel \
                 QtQuick QtQuick.2 QtQuick.Controls QtQuick.Controls.impl \
                 QtQuick.Controls.Basic QtQuick.Controls.Fusion QtQuick.Controls.Material \
                 QtQuick.Controls.Universal QtQuick.Layouts QtQuick.Templates.2 \
                 QtQuick.Window QtQuick.Dialogs QtQuick.Dialogs.quickimpl QtQuick.Shapes \
                 QtQuick.Effects QtQuick.Particles QtQuick3D QtQuick3D.Helpers \
                 QtMultimedia QtLocation QtPositioning QtCharts Qt5Compat QtSensors \
                 Qt.labs.animation Qt.labs.folderlistmodel Qt.labs.qmlmodels QtTest; do
            [[ -d "${TG_QT}/qml/${m}" ]] && { mkdir -p "$p/qml/$m"; cp -rn "${TG_QT}/qml/${m}/"* "$p/qml/$m/" 2>/dev/null || true; }; done; fi
    info "Copying MinGW runtime (from Qt bundle)..."
    for d in libgcc_s_seh-1.dll libstdc++-6.dll libwinpthread-1.dll; do
        [[ -f "${TG_QT}/bin/$d" ]] && cp "${TG_QT}/bin/$d" "$p/"
    done
    # libssp is not in Qt bundle; copy from system MinGW (needed for -lssp link)
    for d in libssp-0.dll; do
        local f; f=$(find /usr/lib/gcc/x86_64-w64-mingw32 -name "$d" -type f 2>/dev/null|head -1)
        [[ -n "$f" ]] && cp "$f" "$p/"
    done
    cat >"$p/qt.conf" <<'QTCF'
[Paths]
Plugins = .
QmlImports = qml
QTCF
    local z="${BUILD_DIR}/QGroundControl-windows-x64-${BTYPE}.zip"
    (cd "${BUILD_DIR}/_pkg" && rm -f "$z" && zip -qr "$z" QGroundControl/)
    [[ -f "$z" ]] && ok "ZIP: $z ($(du -h "$z"|cut -f1))" || warn "ZIP失败"
}

main() {
    parse "$@"
    BUILD_DIR="${ROOT}/build/windows-cross"
    echo -e "\n${G}=== QGC Windows x64 Cross-Compile ===${N}"
    echo "Build: ${BUILD_DIR}  Type: ${BTYPE}  Qt: ${QT_VER}"

    [[ ${DO_DEPS} -eq 1 ]] && install_deps
    for c in x86_64-w64-mingw32-g++-posix cmake ninja; do command -v "$c" >/dev/null || die "缺少 $c"; done
    python3 -c "import aqt" 2>/dev/null || die "缺少 aqtinstall"

    dl_qt
    fix_src
    [[ ${DO_CLEAN} -eq 1 || ! -f "${BUILD_DIR}/CMakeCache.txt" ]] && cmake_cfg
    do_build
    do_inst
    [[ ${DO_ZIP} -eq 1 ]] && do_zip

    echo -e "\n${G}=== Done: ${BUILD_DIR}/Release/QGroundControl.exe ===${N}"
    file "${BUILD_DIR}/Release/QGroundControl.exe" 2>/dev/null || true
    echo ""
}

main "$@"
