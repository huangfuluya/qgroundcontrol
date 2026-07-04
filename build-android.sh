#!/usr/bin/env bash
#
# build-android.sh - QGroundControl Android 构建脚本
#
# 用法:
#   ./build-android.sh [选项]
#
# 选项:
#   -a, --abi <ABI>           Android ABI (arm64-v8a|armeabi-v7a|x86_64|x86)，默认: arm64-v8a
#   -t, --build-type <TYPE>   构建类型 (Debug|Release|RelWithDebInfo)，默认: RelWithDebInfo
#   -j, --jobs <N>            并行构建任务数，默认: 自动检测
#       --ccache              启用 ccache 加速编译
#       --herelink            为 Herelink 设备构建 (使用 Qt 6.6.3)
#       --skip-configure      跳过 CMake 配置步骤
#       --clean               清理构建目录后重新配置
#       --package             生成 APK 包
#       --sign                使用正式密钥签名 APK (需要配置签名信息)
#       --install             安装 APK 到已连接的设备 (需要 adb)
#   -h, --help                显示帮助信息
#
# 环境变量:
#   QT_ROOT_DIR               Qt 安装根目录 (默认: ~/Qt/6.8.3)
#   ANDROID_HOME              Android SDK 路径 (默认: ~/android-sdk)
#   ANDROID_NDK_HOME          Android NDK 路径 (默认: $ANDROID_HOME/ndk/26.1.10909125)
#   JAVA_HOME                 Java JDK 路径 (默认: 自动检测)
#
# 示例:
#   ./build-android.sh                                      # 默认构建
#   ./build-android.sh -a arm64-v8a -t Release -j 8         # 指定参数
#   ./build-android.sh --clean --package --sign             # 清理构建并生成签名 APK
#   ./build-android.sh --herelink                           # Herelink 设备构建
#   ./build-android.sh --package --install                  # 构建 APK 并安装到设备
#
# 前置要求:
#   1. Qt 6.8.3 (或 Herelink 对应 6.6.3) 已安装（包括 Android 工具链）
#      Qt Android 工具链安装:
#        运行 ~/Qt/MaintenanceTool，选择"添加或移除组件"，
#        然后安装 Qt 6.8.3 > Android > arm64-v8a (或其他 ABI)
#   2. Android SDK 已安装（platform-tools, build-tools, platforms;android-34）
#   3. Android NDK 26.1 已安装
#   4. Java JDK 17 已安装
#

set -euo pipefail

# ──────────────────────────── 颜色输出 ────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ──────────────────────────── 默认配置 ────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}"

# ───────────────────── 可通过环境变量覆盖 ─────────────────────
DEFAULT_QT_VERSION="6.8.3"
QT_ROOT_DIR="${QT_ROOT_DIR:-$HOME/Qt/${DEFAULT_QT_VERSION}}"
ANDROID_HOME="${ANDROID_HOME:-$HOME/android-sdk}"
ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-$ANDROID_HOME/ndk/26.1.10909125}"

# ──────────────────────────── 构建参数 ────────────────────────────
ANDROID_ABI="arm64-v8a"
BUILD_TYPE="RelWithDebInfo"
JOBS=""
USE_CCACHE=0
HERELINK_MODE=0
SKIP_CONFIGURE=0
CLEAN_BUILD=0
BUILD_PACKAGE=0
SIGN_APK=0
INSTALL_APK=0

# Qt 版本 (Herelink 使用 6.6.3)
QT_VERSION="${DEFAULT_QT_VERSION}"

# ──────────────────────────── 签名配置 ────────────────────────────
KEYSTORE_PATH="${REPO_ROOT}/deploy/android/android_release.keystore"
KEYSTORE_PASSWORD=""
KEY_ALIAS=""
KEY_PASSWORD=""

# ──────────────────────────── 帮助信息 ────────────────────────────
usage() {
    cat <<'EOF'
用法: ./build-android.sh [选项]

QGroundControl Android 构建脚本

选项:
  -a, --abi <ABI>           Android ABI (arm64-v8a|armeabi-v7a|x86_64|x86)
                             默认: arm64-v8a
  -t, --build-type <TYPE>   构建类型 (Debug|Release|RelWithDebInfo)
                             默认: RelWithDebInfo
  -j, --jobs <N>            并行构建任务数
      --ccache              启用 ccache 加速编译
      --herelink            为 Herelink 设备构建 (使用 Qt 6.6.3)
      --skip-configure      跳过 CMake 配置步骤
      --clean               清理构建目录
      --package             生成 APK 包
      --sign                使用正式密钥签名 APK
      --install             安装 APK 到已连接的设备 (需要 adb)
  -h, --help                显示帮助信息

环境变量:
  QT_ROOT_DIR               Qt 安装根目录 (默认: ~/Qt/6.8.3)
  ANDROID_HOME              Android SDK 路径 (默认: ~/android-sdk)
  ANDROID_NDK_HOME          Android NDK 路径 (默认: $ANDROID_HOME/ndk/26.1.10909125)

示例:
  ./build-android.sh
  ./build-android.sh -a arm64-v8a -t Release -j 8
  ./build-android.sh --clean --package --sign
  ./build-android.sh --herelink --package

EOF
}

# ──────────────────────────── 解析命令行参数 ────────────────────────────
parse_args() {
    while (($#)); do
        case "$1" in
            -a|--abi)
                ANDROID_ABI="$2"
                shift 2
                ;;
            -t|--build-type)
                BUILD_TYPE="$2"
                shift 2
                ;;
            -j|--jobs)
                JOBS="$2"
                shift 2
                ;;
            --ccache)
                USE_CCACHE=1
                shift
                ;;
            --herelink)
                HERELINK_MODE=1
                shift
                ;;
            --skip-configure)
                SKIP_CONFIGURE=1
                shift
                ;;
            --clean)
                CLEAN_BUILD=1
                shift
                ;;
            --package)
                BUILD_PACKAGE=1
                shift
                ;;
            --sign)
                SIGN_APK=1
                shift
                ;;
            --install)
                INSTALL_APK=1
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                error "未知选项: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# ──────────────────────────── 参数验证 ────────────────────────────
validate_args() {
    # 验证 ABI
    case "${ANDROID_ABI}" in
        arm64-v8a|armeabi-v7a|x86_64|x86) ;;
        *)
            error "不支持的 ABI: ${ANDROID_ABI}"
            error "支持的 ABI: arm64-v8a, armeabi-v7a, x86_64, x86"
            exit 1
            ;;
    esac

    # 验证构建类型
    case "${BUILD_TYPE}" in
        Debug|Release|RelWithDebInfo) ;;
        *)
            error "不支持的构建类型: ${BUILD_TYPE}"
            error "支持的构建类型: Debug, Release, RelWithDebInfo"
            exit 1
            ;;
    esac

    # Herelink 模式覆盖 Qt 版本
    if [[ ${HERELINK_MODE} -eq 1 ]]; then
        QT_VERSION="6.6.3"
        QT_ROOT_DIR="${QT_ROOT_DIR/${DEFAULT_QT_VERSION}/${QT_VERSION}}"
        info "Herelink 模式: 使用 Qt ${QT_VERSION}"
    fi

    # 自动检测并行任务数
    if [[ -z "${JOBS}" ]]; then
        if command -v nproc &>/dev/null; then
            JOBS=$(nproc)
        else
            JOBS=4
        fi
    fi
}

# ──────────────────────────── 函数：打印运行信息 ────────────────────────────
print_run_info() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  QGroundControl Android 构建${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo -e "  Qt 版本:     ${GREEN}${QT_VERSION}${NC}"
    echo -e "  构建类型:    ${GREEN}${BUILD_TYPE}${NC}"
    echo -e "  目标 ABI:    ${GREEN}${ANDROID_ABI}${NC}"
    echo -e "  并行任务:    ${GREEN}${JOBS}${NC}"
    echo -e "  使用 ccache:  ${GREEN}$([[ ${USE_CCACHE} -eq 1 ]] && echo "是" || echo "否")${NC}"
    echo -e "  Herelink:    ${GREEN}$([[ ${HERELINK_MODE} -eq 1 ]] && echo "是" || echo "否")${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
}

# ──────────────────────────── 函数：前置检查 ────────────────────────────
check_prerequisites() {
    local has_error=0

    info "检查构建环境..."

    # 构建 Qt Android 工具链路径
    # Qt Android 工具链使用下划线格式的 ABI 名称
    QT_ANDROID_ABI="${ANDROID_ABI//-/_}"  # arm64-v8a -> arm64_v8a
    QT_ANDROID_TOOLCHAIN="${QT_ROOT_DIR}/android_${QT_ANDROID_ABI}"
    QT_CMAKE="${QT_ANDROID_TOOLCHAIN}/bin/qt-cmake"
    QT_TOOLCHAIN_FILE="${QT_ANDROID_TOOLCHAIN}/lib/cmake/Qt6/qt.toolchain.cmake"

    # 检查 Qt Android 工具链
    if [[ ! -d "${QT_ANDROID_TOOLCHAIN}" ]]; then
        error "Qt Android 工具链未安装: ${QT_ANDROID_TOOLCHAIN}"
        error ""
        error "请安装 Qt Android 工具链:"
        error "  1. 运行: ~/Qt/MaintenanceTool"
        error "  2. 选择'添加或移除组件'"
        error "  3. 安装: Qt ${QT_VERSION} > Android > ${ANDROID_ABI}"
        has_error=1
    else
        success "Qt Android 工具链: ${QT_ANDROID_TOOLCHAIN}"
    fi

    # 检查 qt-cmake
    if [[ ! -x "${QT_CMAKE}" ]]; then
        error "qt-cmake 未找到: ${QT_CMAKE}"
        has_error=1
    else
        success "qt-cmake: ${QT_CMAKE}"
    fi

    # 检查 Android SDK
    if [[ ! -d "${ANDROID_HOME}" ]]; then
        error "Android SDK 未安装: ${ANDROID_HOME}"
        has_error=1
    else
        success "Android SDK: ${ANDROID_HOME}"
    fi

    # 检查 Android NDK
    if [[ ! -d "${ANDROID_NDK_HOME}" ]]; then
        error "Android NDK 未安装: ${ANDROID_NDK_HOME}"
        has_error=1
    else
        success "Android NDK: ${ANDROID_NDK_HOME}"
    fi

    # 检查 Java (要求 JDK 17)
    if ! command -v java &>/dev/null; then
        error "Java 未安装"
        error "请安装: sudo apt install openjdk-17-jdk-headless"
        has_error=1
    else
        local java_ver
        java_ver=$(java -version 2>&1 | head -1)
        success "Java: ${java_ver}"
    fi

    # 自动检测 JAVA_HOME
    if [[ -z "${JAVA_HOME:-}" ]]; then
        if command -v java &>/dev/null; then
            JAVA_HOME=$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")
            export JAVA_HOME
        elif [[ -d /usr/lib/jvm/java-17-openjdk-amd64 ]]; then
            JAVA_HOME="/usr/lib/jvm/java-17-openjdk-amd64"
        elif [[ -d /usr/lib/jvm/default-java ]]; then
            JAVA_HOME="/usr/lib/jvm/default-java"
        fi
    fi

    # 检查 Android API 级别
    local api_level=34
    if [[ -d "${ANDROID_HOME}/platforms/android-${api_level}" ]]; then
        success "Android API 级别: ${api_level}"
    else
        warn "Android API 级别 ${api_level} 未安装，尝试使用可用版本"
        if command -v sdkmanager &>/dev/null; then
            warn "运行 'sdkmanager \"platforms;android-${api_level}\"' 安装"
        fi
    fi

    # 检查 Ninja
    if ! command -v ninja &>/dev/null; then
        warn "Ninja 未安装，将使用默认构建系统"
        warn "安装: sudo apt install ninja-build"
    else
        success "Ninja: $(ninja --version)"
    fi

    # 检查 ccache (如果启用了)
    if [[ ${USE_CCACHE} -eq 1 ]]; then
        if command -v ccache &>/dev/null; then
            success "ccache: $(ccache --version | head -1)"
        else
            warn "ccache 未安装，已禁用 ccache 模式"
            warn "安装: sudo apt install ccache"
            USE_CCACHE=0
        fi
    fi

    if [[ ${has_error} -eq 1 ]]; then
        error ""
        error "请先安装缺失的组件，然后重新运行此脚本"
        exit 1
    fi
}

# ──────────────────────────── 函数：设置环境变量 ────────────────────────────
setup_environment() {
    export ANDROID_HOME
    export ANDROID_NDK_HOME
    export ANDROID_ABI
    export QT_ROOT_DIR
    export JAVA_HOME

    # ANDROID_NDK_ROOT 是 Qt Android toolchain 检查的关键环境变量
    # Qt toolchain 内部会查找 ${ANDROID_NDK_ROOT}/build/cmake/android.toolchain.cmake
    export ANDROID_NDK_ROOT="${ANDROID_NDK_HOME}"
    export ANDROID_SDK_ROOT="${ANDROID_HOME}"

    # 设置 PATH
    # 使用 headless JDK 路径: jdk-17 -> java-17-openjdk-amd64
    if [[ -z "${JAVA_HOME:-}" ]]; then
        for candidate in /usr/lib/jvm/java-17-openjdk-amd64 /usr/lib/jvm/default-java; do
            if [[ -d "${candidate}" ]]; then
                JAVA_HOME="${candidate}"
                break
            fi
        done
    fi

    export PATH="${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools:${JAVA_HOME}/bin:${PATH}"

    info "环境变量:"
    info "  ANDROID_HOME      = ${ANDROID_HOME}"
    info "  ANDROID_NDK_HOME  = ${ANDROID_NDK_HOME}"
    info "  ANDROID_NDK_ROOT  = ${ANDROID_NDK_ROOT}"
    info "  ANDROID_ABI       = ${ANDROID_ABI}"
    info "  JAVA_HOME         = ${JAVA_HOME}"
    info "  QT_ROOT_DIR       = ${QT_ROOT_DIR}"
}

# ──────────────────────────── 函数：清理构建目录 ────────────────────────────
clean_build() {
    if [[ -d "${BUILD_DIR}" ]]; then
        info "清理构建目录: ${BUILD_DIR}"
        rm -rf "${BUILD_DIR}"
        success "构建目录已清理"
    fi
}

# ──────────────────────────── 函数：CMake 配置 ────────────────────────────
configure_cmake() {
    info "配置 CMake..."
    info "  Qt 工具链: ${QT_TOOLCHAIN_FILE}"
    info "  构建目录:  ${BUILD_DIR}"

    # 设置 CPM 缓存目录（共享缓存，加速重复构建）
    local cpm_cache="${REPO_ROOT}/build/cpm_cache"
    mkdir -p "${cpm_cache}"

    local cmake_args=(
        -S "${REPO_ROOT}"
        -B "${BUILD_DIR}"
        -G Ninja
        -DCMAKE_BUILD_TYPE="${BUILD_TYPE}"
        -DCMAKE_TOOLCHAIN_FILE="${QT_TOOLCHAIN_FILE}"
        -DANDROID_ABI="${ANDROID_ABI}"
        -DANDROID_NDK="${ANDROID_NDK_HOME}"
        -DQT_HOST_PATH="${QT_ROOT_DIR}/gcc_64"
        -DQGC_CPM_SOURCE_CACHE="${cpm_cache}"
        -DQGC_ENABLE_GST_VIDEOSTREAMING=OFF
        -DQGC_ENABLE_QT_VIDEOSTREAMING=ON
    )

    # Herelink 模式
    if [[ ${HERELINK_MODE} -eq 1 ]]; then
        cmake_args+=(-DQGC_ENABLE_HERELINK=ON)
    fi

    # ccache
    if [[ ${USE_CCACHE} -eq 1 ]]; then
        cmake_args+=(
            -DQGC_USE_CACHE=ON
            -DCMAKE_C_COMPILER_LAUNCHER=ccache
            -DCMAKE_CXX_COMPILER_LAUNCHER=ccache
        )
    fi

    "${QT_CMAKE}" "${cmake_args[@]}"

    if [[ $? -ne 0 ]]; then
        error "CMake 配置失败!"
        exit 1
    fi

    success "CMake 配置完成"
}

# ──────────────────────────── 函数：构建项目 ────────────────────────────
build_project() {
    info "构建项目..."
    local start_time
    start_time=$(date +%s)

    local build_args=(
        --build "${BUILD_DIR}"
        --config "${BUILD_TYPE}"
        --parallel "${JOBS}"
    )

    cmake "${build_args[@]}"

    local build_ret=$?
    local end_time
    end_time=$(date +%s)

    if [[ ${build_ret} -ne 0 ]]; then
        error "构建失败! 耗时: $(( (end_time - start_time) / 60 )) 分 $(( (end_time - start_time) % 60 )) 秒"
        exit 1
    fi

    success "构建成功! 耗时: $(( (end_time - start_time) / 60 )) 分 $(( (end_time - start_time) % 60 )) 秒"
}

# ──────────────────────────── 函数：查找 androiddeployqt ────────────────────────────
find_androiddeployqt() {
    # 优先从 Qt Android 工具链中查找
    local deploy_qt="${QT_ANDROID_TOOLCHAIN}/bin/androiddeployqt"
    if [[ -x "${deploy_qt}" ]]; then
        echo "${deploy_qt}"
        return 0
    fi

    # 尝试从 PATH 查找
    if command -v androiddeployqt &>/dev/null; then
        echo "$(command -v androiddeployqt)"
        return 0
    fi

    error "androiddeployqt 未找到"
    return 1
}

# ──────────────────────────── 函数：查找 deployment settings JSON ────────────────────────────
find_deployment_json() {
    local json_file

    # 常用的文件名模式
    local patterns=(
        "${BUILD_DIR}/android-QGroundControl-deployment-settings.json"
        "${BUILD_DIR}/android-build-deployment-settings.json"
    )

    for p in "${patterns[@]}"; do
        if [[ -f "${p}" ]]; then
            echo "${p}"
            return 0
        fi
    done

    # 回退：在构建目录中查找
    json_file=$(find "${BUILD_DIR}" -maxdepth 2 -name "*deployment-settings.json" -print -quit 2>/dev/null)
    if [[ -n "${json_file}" ]]; then
        echo "${json_file}"
        return 0
    fi

    return 1
}

# ──────────────────────────── 函数：打包 APK ────────────────────────────
package_apk() {
    info "打包 APK..."

    local deploy_qt
    deploy_qt=$(find_androiddeployqt) || exit 1

    local apk_dir="${BUILD_DIR}/android-apk"
    mkdir -p "${apk_dir}"

    local deployment_json
    deployment_json=$(find_deployment_json)

    if [[ -z "${deployment_json}" ]]; then
        warn "未找到 deployment settings JSON 文件"
        warn "尝试手动调用 androiddeployqt..."

        # 尝试找到 JSON 文件或通过 cpack 打包
        if command -v cpack &>/dev/null; then
            info "使用 cpack 打包..."
            cd "${BUILD_DIR}"
            cpack -G APK 2>&1 || {
                error "CPack APK 打包失败"
                exit 1
            }
            success "APK 打包完成 (cpack)"
        else
            error "无法打包 APK，缺少 deployment settings 且 cpack 不可用"
            exit 1
        fi
        return 0
    fi

    info "使用 deployment settings: ${deployment_json}"

    local deploy_args=(
        --input "${deployment_json}"
        --output "${apk_dir}"
        --android-platform android-34
        --jdk "${JAVA_HOME}"
        --gradle
    )

    # 签名参数
    if [[ ${SIGN_APK} -eq 1 ]]; then
        if [[ -f "${KEYSTORE_PATH}" ]]; then
            info "使用签名密钥: ${KEYSTORE_PATH}"
            deploy_args+=(--sign "${KEYSTORE_PATH}")
            [[ -n "${KEYSTORE_PASSWORD}" ]] && deploy_args+=(--storepass "${KEYSTORE_PASSWORD}")
            [[ -n "${KEY_ALIAS}" ]] && deploy_args+=(--alias "${KEY_ALIAS}")
            [[ -n "${KEY_PASSWORD}" ]] && deploy_args+=(--keypass "${KEY_PASSWORD}")
        else
            warn "签名密钥未找到: ${KEYSTORE_PATH}"
            warn "将生成未签名的 APK (debug 签名)"
        fi
    else
        info "使用 Debug 签名 (默认)"
    fi

    "${deploy_qt}" "${deploy_args[@]}"

    if [[ $? -ne 0 ]]; then
        error "APK 打包失败!"
        exit 1
    fi

    success "APK 打包完成!"
    info "APK 文件:"
    find "${apk_dir}" -name "*.apk" -type f -exec ls -lh {} \; 2>/dev/null || {
        # 也可能在 build 目录的其他位置
        find "${BUILD_DIR}" -name "*.apk" -type f -exec ls -lh {} \;
    }
}

# ──────────────────────────── 函数：安装 APK 到设备 ────────────────────────────
install_apk() {
    info "安装 APK 到已连接的设备..."

    if ! command -v adb &>/dev/null; then
        error "adb 未安装，请安装: sudo apt install adb"
        exit 1
    fi

    # 检查设备连接
    local devices
    devices=$(adb devices 2>/dev/null | grep -v "List of devices" | grep -c "device$" || true)
    if [[ "${devices}" -eq 0 ]]; then
        error "未检测到已连接的 Android 设备"
        error "请确认:"
        error "  1. 设备已通过 USB 连接"
        error "  2. 设备已开启 USB 调试模式"
        error "  3. 已授权此计算机的调试连接"
        exit 1
    fi

    success "检测到 ${devices} 个设备"

    # 查找 APK
    local apk_file
    apk_file=$(find "${BUILD_DIR}" -name "*.apk" -type f -print -quit 2>/dev/null)

    if [[ -z "${apk_file}" ]]; then
        error "未找到 APK 文件，请先使用 --package 生成 APK"
        exit 1
    fi

    info "安装: ${apk_file}"
    adb install -r "${apk_file}"

    if [[ $? -ne 0 ]]; then
        error "APK 安装失败!"
        warn "可以尝试手动安装: adb install -r ${apk_file}"
        exit 1
    fi

    success "APK 安装成功!"
    info "可以在设备上启动 QGroundControl"
}

# ──────────────────────────── 主函数 ────────────────────────────
main() {
    parse_args "$@"
    validate_args

    # Qt Android 工具链路径 (在 validate_args 中设置了 QT_VERSION 后)
    QT_ANDROID_ABI="${ANDROID_ABI//-/_}"
    QT_ANDROID_TOOLCHAIN="${QT_ROOT_DIR}/android_${QT_ANDROID_ABI}"
    QT_CMAKE="${QT_ANDROID_TOOLCHAIN}/bin/qt-cmake"
    QT_TOOLCHAIN_FILE="${QT_ANDROID_TOOLCHAIN}/lib/cmake/Qt6/qt.toolchain.cmake"

    # 构建目录命名
    local ccache_suffix=""
    [[ ${USE_CCACHE} -eq 1 ]] && ccache_suffix="-ccache"
    BUILD_DIR="${REPO_ROOT}/build/android-${ANDROID_ABI}-${BUILD_TYPE}${ccache_suffix}"

    print_run_info
    check_prerequisites
    setup_environment

    # ── 清理 ──
    if [[ ${CLEAN_BUILD} -eq 1 ]]; then
        clean_build
    fi

    # ── 配置 ──
    if [[ ${SKIP_CONFIGURE} -eq 0 || ! -f "${BUILD_DIR}/CMakeCache.txt" ]]; then
        configure_cmake
    else
        info "跳过 CMake 配置 (已存在 CMakeCache.txt)"
    fi

    # ── 构建 ──
    build_project

    # ── 打包 ──
    if [[ ${BUILD_PACKAGE} -eq 1 ]]; then
        package_apk
    fi

    # ── 安装 ──
    if [[ ${INSTALL_APK} -eq 1 ]]; then
        if [[ ${BUILD_PACKAGE} -eq 0 ]]; then
            warn "--install 需要先打包，自动启用 --package"
            package_apk
        fi
        install_apk
    fi

    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  QGroundControl Android 构建完成!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo -e "  构建目录: ${BUILD_DIR}"
    if [[ ${BUILD_PACKAGE} -eq 1 ]]; then
        echo -e "  APK 文件: "
        find "${BUILD_DIR}" -name "*.apk" -type f -exec echo -e "    {}" \; 2>/dev/null || true
    fi
    echo -e "${GREEN}========================================${NC}"
    echo ""
}

main "$@"