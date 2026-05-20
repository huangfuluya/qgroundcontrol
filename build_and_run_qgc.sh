#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}"

BUILD_TYPE="Debug"
BUILD_DIR="${REPO_ROOT}/build"
QT_CMAKE="${QT_CMAKE:-}"
PKG_CONFIG_BIN="${PKG_CONFIG_BIN:-}"
MAVLINK_REPO="${MAVLINK_REPO:-}"
MAVLINK_TAG="${MAVLINK_TAG:-}"
JOBS=""
SKIP_CONFIGURE=0
CLEAN_BUILD=0
RUN_ARGS=()

usage() {
    cat <<'EOF'
Usage: ./build_and_run_qgc.sh [options] [-- <qgc runtime args>]

Build and launch QGroundControl from this repository.

Options:
  -t, --build-type <Debug|Release>  CMake build type (default: Debug)
  -b, --build-dir <path>            Build directory (default: ./build)
  -q, --qt-cmake <path>             Path to qt-cmake binary
  -p, --pkg-config <path>           Path to pkg-config binary (default: /usr/bin/pkg-config)
  -m, --mavlink-tag <ref>           Override MAVLink git ref (tag/branch/commit)
      --mavlink-repo <url>          Override MAVLink git repository URL
  -j, --jobs <N>                    Parallel build jobs (cmake --build --parallel N)
      --skip-configure              Skip CMake configure step and only build/run
      --clean                       Remove build directory before configuring
  -h, --help                        Show help

Environment variables:
  QT_CMAKE                           Alternative way to provide qt-cmake path
  PKG_CONFIG_BIN                     Alternative way to provide pkg-config path
  MAVLINK_TAG                        Alternative way to provide MAVLink git ref
  MAVLINK_REPO                       Alternative way to provide MAVLink git repo

Examples:
  ./build_and_run_qgc.sh
  ./build_and_run_qgc.sh -t Release -j 8
  ./build_and_run_qgc.sh -q ~/Qt/6.8.3/gcc_64/bin/qt-cmake
  ./build_and_run_qgc.sh -- --logging:full
EOF
}

resolve_qt_cmake() {
    if [[ -n "${QT_CMAKE}" ]]; then
        if [[ -x "${QT_CMAKE}" ]]; then
            echo "${QT_CMAKE}"
            return 0
        fi
        echo "Error: qt-cmake not executable: ${QT_CMAKE}" >&2
        exit 1
    fi

    if command -v qt-cmake >/dev/null 2>&1; then
        command -v qt-cmake
        return 0
    fi

    local candidates=(
        "$HOME/Qt/6.8.3/gcc_64/bin/qt-cmake"
        "/opt/Qt/6.8.3/gcc_64/bin/qt-cmake"
    )

    local candidate
    for candidate in "${candidates[@]}"; do
        if [[ -x "${candidate}" ]]; then
            echo "${candidate}"
            return 0
        fi
    done

    cat >&2 <<'EOF'
Error: qt-cmake not found.
Install Qt 6.8.3 (Linux gcc_64), then re-run with one of:
  1) export QT_CMAKE=/path/to/qt-cmake
  2) ./build_and_run_qgc.sh -q /path/to/qt-cmake
EOF
    exit 1
}

find_qgc_binary() {
    local build_dir="$1"
    local build_type="$2"

    local candidates=(
        "${build_dir}/${build_type}/QGroundControl"
        "${build_dir}/QGroundControl"
        "${build_dir}/src/QGroundControl"
    )

    local candidate
    for candidate in "${candidates[@]}"; do
        if [[ -x "${candidate}" ]]; then
            echo "${candidate}"
            return 0
        fi
    done

    return 1
}

resolve_pkg_config() {
    if [[ -n "${PKG_CONFIG_BIN}" ]]; then
        if [[ -x "${PKG_CONFIG_BIN}" ]]; then
            echo "${PKG_CONFIG_BIN}"
            return 0
        fi
        echo "Error: pkg-config not executable: ${PKG_CONFIG_BIN}" >&2
        exit 1
    fi

    if [[ -x "/usr/bin/pkg-config" ]]; then
        echo "/usr/bin/pkg-config"
        return 0
    fi

    if command -v pkg-config >/dev/null 2>&1; then
        command -v pkg-config
        return 0
    fi

    echo "Error: pkg-config not found" >&2
    exit 1
}

qt_has_quick3d() {
    local qt_cmake_bin="$1"
    local qt_root
    qt_root="$(cd "$(dirname "${qt_cmake_bin}")/.." && pwd)"

    [[ -f "${qt_root}/lib/cmake/Qt6Quick3D/Qt6Quick3DConfig.cmake" ]]
}

extract_cmake_cache_value() {
    local key="$1"
    local file="$2"
    sed -n "s/^${key}\\s\+\"\\([^\"]*\\)\".*/\\1/p" "${file}" | head -n 1
}

git_ref_exists() {
    local repo="$1"
    local ref="$2"

    if [[ -z "${repo}" || -z "${ref}" ]]; then
        return 1
    fi

    git ls-remote "${repo}" 2>/dev/null | awk '{print $1" "$2}' | \
        grep -Eq "^${ref}[[:space:]]|[[:space:]]refs/(heads|tags)/${ref}$"
}

while (($#)); do
    case "$1" in
        -t|--build-type)
            BUILD_TYPE="$2"
            shift 2
            ;;
        -b|--build-dir)
            BUILD_DIR="$2"
            shift 2
            ;;
        -q|--qt-cmake)
            QT_CMAKE="$2"
            shift 2
            ;;
        -p|--pkg-config)
            PKG_CONFIG_BIN="$2"
            shift 2
            ;;
        -m|--mavlink-tag)
            MAVLINK_TAG="$2"
            shift 2
            ;;
        --mavlink-repo)
            MAVLINK_REPO="$2"
            shift 2
            ;;
        -j|--jobs)
            JOBS="$2"
            shift 2
            ;;
        --skip-configure)
            SKIP_CONFIGURE=1
            shift
            ;;
        --clean)
            CLEAN_BUILD=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            RUN_ARGS=("$@")
            break
            ;;
        *)
            echo "Error: unknown option: $1" >&2
            usage
            exit 1
            ;;
    esac
done

if [[ "${BUILD_TYPE}" != "Debug" && "${BUILD_TYPE}" != "Release" ]]; then
    echo "Error: --build-type must be Debug or Release" >&2
    exit 1
fi

if [[ "${CLEAN_BUILD}" -eq 1 ]]; then
    echo "[QGC] Cleaning build directory: ${BUILD_DIR}"
    rm -rf "${BUILD_DIR}"
fi

QT_CMAKE_BIN="$(resolve_qt_cmake)"
PKG_CONFIG_BIN="$(resolve_pkg_config)"

if [[ -z "${MAVLINK_REPO}" ]]; then
    MAVLINK_REPO="$(extract_cmake_cache_value "set(QGC_MAVLINK_GIT_REPO" "${REPO_ROOT}/cmake/CustomOptions.cmake")"
fi
if [[ -z "${MAVLINK_TAG}" ]]; then
    MAVLINK_TAG="$(extract_cmake_cache_value "set(QGC_MAVLINK_GIT_TAG" "${REPO_ROOT}/cmake/CustomOptions.cmake")"
fi

if [[ -n "${MAVLINK_REPO}" && -n "${MAVLINK_TAG}" ]] && ! git_ref_exists "${MAVLINK_REPO}" "${MAVLINK_TAG}"; then
    echo "[QGC] MAVLink ref ${MAVLINK_TAG} not found in ${MAVLINK_REPO}, falling back to master."
    MAVLINK_TAG="master"
fi

CONFIGURE_ARGS=(
    -S "${REPO_ROOT}"
    -B "${BUILD_DIR}"
    -G Ninja
    -DCMAKE_BUILD_TYPE="${BUILD_TYPE}"
    -DPKG_CONFIG_EXECUTABLE="${PKG_CONFIG_BIN}"
)

if [[ -n "${MAVLINK_REPO}" ]]; then
    CONFIGURE_ARGS+=("-DQGC_MAVLINK_GIT_REPO=${MAVLINK_REPO}")
fi
if [[ -n "${MAVLINK_TAG}" ]]; then
    CONFIGURE_ARGS+=("-DQGC_MAVLINK_GIT_TAG=${MAVLINK_TAG}")
fi

if ! qt_has_quick3d "${QT_CMAKE_BIN}"; then
    echo "[QGC] QtQuick3D not found in current Qt kit, disabling Viewer3D for this build."
    CONFIGURE_ARGS+=("-DQGC_VIEWER3D=OFF")
fi

echo "[QGC] Repository: ${REPO_ROOT}"
echo "[QGC] Build type: ${BUILD_TYPE}"
echo "[QGC] Build dir: ${BUILD_DIR}"
echo "[QGC] qt-cmake: ${QT_CMAKE_BIN}"
echo "[QGC] pkg-config: ${PKG_CONFIG_BIN}"
if [[ -n "${MAVLINK_REPO}" ]]; then
    echo "[QGC] MAVLink repo: ${MAVLINK_REPO}"
fi
if [[ -n "${MAVLINK_TAG}" ]]; then
    echo "[QGC] MAVLink ref: ${MAVLINK_TAG}"
fi

if [[ "${SKIP_CONFIGURE}" -eq 0 || ! -f "${BUILD_DIR}/CMakeCache.txt" ]]; then
    echo "[QGC] Configuring project..."
    "${QT_CMAKE_BIN}" "${CONFIGURE_ARGS[@]}"
else
    echo "[QGC] Skipping configure (existing CMakeCache.txt found)."
fi

echo "[QGC] Building project..."
if [[ -n "${JOBS}" ]]; then
    cmake --build "${BUILD_DIR}" --config "${BUILD_TYPE}" --parallel "${JOBS}"
else
    cmake --build "${BUILD_DIR}" --config "${BUILD_TYPE}"
fi

QGC_BIN="$(find_qgc_binary "${BUILD_DIR}" "${BUILD_TYPE}" || true)"
if [[ -z "${QGC_BIN}" ]]; then
    echo "Error: QGroundControl binary not found in ${BUILD_DIR}" >&2
    echo "Tried:"
    echo "  - ${BUILD_DIR}/${BUILD_TYPE}/QGroundControl"
    echo "  - ${BUILD_DIR}/QGroundControl"
    echo "  - ${BUILD_DIR}/src/QGroundControl"
    exit 1
fi

echo "[QGC] Launching: ${QGC_BIN} ${RUN_ARGS[*]:-}"
exec "${QGC_BIN}" "${RUN_ARGS[@]}"
