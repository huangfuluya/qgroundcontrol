#!/usr/bin/env python3
"""QGroundControl Windows Build & Launch Script.

Usage:
    python build_qgc.py            # Configure + Build + Run (default)
    python build_qgc.py configure  # Only configure CMake
    python build_qgc.py build      # Only build (incremental)
    python build_qgc.py run        # Only launch QGC
    python build_qgc.py rebuild    # Clean + Configure + Build
    python build_qgc.py clean      # Clean build directory
    python build_qgc.py deploy     # Configure + Build + Install (windeployqt, for distribution)
    python build_qgc.py all        # Configure + Build + Run

Environment variables (optional overrides):
    QT_ROOT_DIR     - Qt installation path (default: auto-detected)
    BUILD_TYPE      - Debug or Release (default: Debug; deploy defaults to Release)
    BUILD_DIR       - Build directory (default: build; deploy defaults to build_release)
    JOBS            - Parallel build jobs (default: CPU cores - 1)
    VS_PATH         - Visual Studio 2022 path (default: auto-detected)
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
from pathlib import Path

# ============================================================================
# Configuration
# ============================================================================

SCRIPT_DIR = Path(__file__).resolve().parent

# Qt versions to search for, newest first
QT_VERSIONS = [
    "6.11.1", "6.11.0",
    "6.10.1", "6.10.0",
    "6.9.1", "6.9.0",
    "6.8.3", "6.8.2", "6.8.1", "6.8.0",
    "6.7.3", "6.7.2", "6.7.1", "6.7.0",
    "6.6.3", "6.6.2", "6.6.1", "6.6.0",
]

QT_KITS = ["msvc2022_64", "msvc2019_64"]

# Visual Studio 2022 editions to search for
VS_PATHS = [
    r"C:\Program Files\Microsoft Visual Studio\2022\Community",
    r"C:\Program Files\Microsoft Visual Studio\2022\Professional",
    r"C:\Program Files\Microsoft Visual Studio\2022\Enterprise",
    r"C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools",
]


# ============================================================================
# Helpers
# ============================================================================

def echo(msg: str = "") -> None:
    print(msg)


def detect_qt() -> tuple[Path | None, str | None]:
    """Detect Qt installation. Returns (qt_root, version) or (None, None)."""
    env_qt = os.environ.get("QT_ROOT_DIR")
    if env_qt:
        qt_root = Path(env_qt)
        qt_cmake = qt_root / "bin" / "qt-cmake.bat"
        if qt_cmake.exists():
            # Infer version from path
            version = None
            for v in QT_VERSIONS:
                if v in str(qt_root):
                    version = v
                    break
            if version is None:
                version = "6.10.0"
            return qt_root, version
        echo(f"[ERROR] qt-cmake.bat not found at: {qt_cmake}")
        sys.exit(1)

    # Auto-detect
    for ver in QT_VERSIONS:
        for kit in QT_KITS:
            qt_root = Path(f"C:/Qt/{ver}/{kit}")
            qt_cmake = qt_root / "bin" / "qt-cmake.bat"
            if qt_cmake.exists():
                return qt_root, ver

    return None, None


def detect_vs() -> Path | None:
    """Detect Visual Studio 2022 installation."""
    env_vs = os.environ.get("VS_PATH")
    if env_vs:
        vs_path = Path(env_vs)
        if (vs_path / "VC/Auxiliary/Build/vcvars64.bat").exists():
            return vs_path
        echo(f"[ERROR] vcvars64.bat not found in: {vs_path}")
        sys.exit(1)

    for vs_path in VS_PATHS:
        vcvars = Path(vs_path) / "VC/Auxiliary/Build/vcvars64.bat"
        if vcvars.exists():
            return Path(vs_path)

    return None


def setup_msvc_env(vs_path: Path) -> dict[str, str]:
    """Run vcvars64.bat and return the resulting environment."""
    vcvars = vs_path / "VC/Auxiliary/Build/vcvars64.bat"
    echo(f"      VS Path: {vs_path}")

    # Run vcvars64.bat and capture the environment via "cmd /c vcvars && set"
    # Use shell=True so cmd.exe interprets the && and redirections
    cmd = f'"{vcvars}" >nul 2>&1 && set'
    result = subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        shell=True,
    )

    if result.returncode != 0:
        echo(f"[ERROR] Failed to initialize MSVC environment (exit code: {result.returncode})")
        if result.stderr:
            echo(result.stderr)
        if result.stdout:
            echo(result.stdout[:500])
        sys.exit(1)

    # Parse environment variables from output
    env = dict(os.environ)
    for line in result.stdout.splitlines():
        if "=" in line:
            key, _, value = line.partition("=")
            env[key] = value

    return env


def get_qt_version_range(version: str) -> tuple[str, str]:
    """Build Qt version range (min, max) from version string."""
    parts = version.split(".")
    major = parts[0] if len(parts) > 0 else "6"
    minor = parts[1] if len(parts) > 1 else "10"
    ver_min = f"{major}.{minor}.0"
    ver_max = version
    return ver_min, ver_max


# ============================================================================
# Actions
# ============================================================================

def do_clean(build_dir: Path) -> int:
    echo(f"[CLEAN] Removing {build_dir} ...")
    if build_dir.exists():
        shutil.rmtree(build_dir, ignore_errors=True)
    echo("[CLEAN] Done.")
    return 0


def detect_gstreamer_version() -> str | None:
    """Detect installed GStreamer version via gst-launch-1.0 --version."""
    # Search paths: env var first, then common install locations (newest first)
    candidates = []
    env_gst = os.environ.get("GSTREAMER_1_0_ROOT_MSVC_X86_64", "")
    if env_gst:
        candidates.append(env_gst.rstrip("\\/"))
    candidates.extend([
        r"C:\Program Files\gstreamer\1.0\msvc_x86_64",
        r"C:\gstreamer\1.0\msvc_x86_64",
    ])
    for gst_root in candidates:
        gst_launch = Path(gst_root) / "bin" / "gst-launch-1.0.exe"
        if gst_launch.exists():
            try:
                result = subprocess.run(
                    [str(gst_launch), "--version"],
                    capture_output=True, text=True, timeout=10,
                )
                for line in result.stdout.splitlines():
                    if "GStreamer" in line and line[0].isdigit():
                        return line.split()[1]
            except Exception:
                pass
    return None


def do_configure(
    qt_root: Path,
    qt_cmake: Path,
    qt_ver_min: str,
    qt_ver_max: str,
    build_type: str,
    build_dir: Path,
    env: dict[str, str],
) -> int:
    echo("[CONFIGURE] Running CMake configuration...")

    cmake_prefix_path = str(qt_root)
    env = {**env, "CMAKE_PREFIX_PATH": cmake_prefix_path}

    cmd = [
        str(qt_cmake),
        "-S", str(SCRIPT_DIR),
        "-B", str(build_dir),
        "-G", "Ninja",
        f"-DCMAKE_BUILD_TYPE={build_type}",
        "-DQGC_BUILD_TESTING=OFF",
        f"-DQGC_QT_MINIMUM_VERSION={qt_ver_min}",
        f"-DQGC_QT_MAXIMUM_VERSION={qt_ver_max}",
        "-DQGC_ENABLE_WERROR=OFF",
        "-DCMAKE_EXPORT_COMPILE_COMMANDS=ON",
    ]

    # GStreamer version override: if installed version < 1.28.4 (project requirement),
    # override GStreamer_FIND_VERSION to accept the installed version.
    gst_ver = detect_gstreamer_version()
    if gst_ver:
        def _ver_tuple(v: str) -> tuple:
            try:
                return tuple(int(x) for x in v.split("."))
            except ValueError:
                return (0,)
        if _ver_tuple(gst_ver) < _ver_tuple("1.28.4"):
            echo(f"  GStreamer {gst_ver} < 1.28.4 (required), overriding version check")
            cmd.append(f"-DGStreamer_FIND_VERSION={gst_ver}")

    echo(f"  Command: {' '.join(cmd)}")
    echo()

    result = subprocess.run(cmd, env=env)

    if result.returncode != 0:
        echo()
        echo("[ERROR] CMake configuration failed.")
        echo()
        echo("Troubleshooting:")
        echo("  - GStreamer SDK is auto-downloaded during configure (needs internet)")
        echo("  - If GStreamer download fails, install manually from:")
        echo("    https://gstreamer.freedesktop.org/download/")
        echo("  - Then set GSTREAMER_1_0_ROOT_MSVC_X86_64 to the install path")
        return 1

    echo()
    echo("[CONFIGURE] Configuration successful.")
    return 0


def do_build(build_dir: Path, build_type: str, jobs: int, env: dict[str, str]) -> int:
    if not (build_dir / "CMakeCache.txt").exists():
        echo("[ERROR] Build directory not configured. Run 'configure' first.")
        return 1

    echo(f"[BUILD] Building QGroundControl ({build_type}, {jobs} jobs)...")
    cmd = [
        "cmake", "--build", str(build_dir),
        "--config", build_type,
        "--parallel", str(jobs),
    ]
    result = subprocess.run(cmd, env=env)

    if result.returncode != 0:
        echo()
        echo("[ERROR] Build failed.")
        return 1

    echo()
    exe_path = build_dir / "QGroundControl.exe"
    echo(f"[BUILD] Build successful.")
    echo(f"       Binary: {exe_path}")
    return 0


def do_run(build_dir: Path, build_type: str, qt_root: Path) -> int:
    exe_path = build_dir / "QGroundControl.exe"
    if not exe_path.exists():
        # Try Debug/Release subdirectory (multi-config fallback)
        exe_path = build_dir / build_type / "QGroundControl.exe"
    if not exe_path.exists():
        echo("[ERROR] QGroundControl.exe not found.")
        echo("        Build first with: python build_qgc.py build")
        return 1

    # Set up PATH for Qt and GStreamer DLLs
    run_env = dict(os.environ)
    extra_paths = [str(qt_root / "bin")]

    # Find GStreamer bin directory (check env var, then common paths)
    gst_root = os.environ.get("GSTREAMER_1_0_ROOT_MSVC_X86_64", "").rstrip("\\/")
    if not gst_root or not (Path(gst_root) / "bin").exists():
        for candidate in [
            r"C:\Program Files\gstreamer\1.0\msvc_x86_64",
            r"C:\gstreamer\1.0\msvc_x86_64",
        ]:
            if (Path(candidate) / "bin").exists():
                gst_root = candidate
                break

    if gst_root:
        extra_paths.append(str(Path(gst_root) / "bin"))

    run_env["PATH"] = ";".join(extra_paths) + ";" + run_env.get("PATH", "")

    echo(f"[RUN] Launching {exe_path} ...")
    subprocess.Popen([str(exe_path)], env=run_env)
    return 0


def do_deploy(
    qt_root: Path,
    qt_cmake: Path,
    qt_ver_min: str,
    qt_ver_max: str,
    build_type: str,
    build_dir: Path,
    jobs: int,
    env: dict[str, str],
) -> int:
    """Configure + Build + cmake --install (windeployqt) for distribution.

    Produces a self-contained staging/ directory ready to copy to another PC.
    """
    echo("=" * 68)
    echo(" QGC DEPLOY — Full Release Build + windeployqt")
    echo("=" * 68)
    echo()

    # Stage 1: Configure
    rc = do_configure(qt_root, qt_cmake, qt_ver_min, qt_ver_max,
                      build_type, build_dir, env)
    if rc != 0:
        return rc

    # Stage 2: Build
    rc = do_build(build_dir, build_type, jobs, env)
    if rc != 0:
        return rc

    # Stage 3: cmake --install (triggers windeployqt)
    echo()
    echo("[INSTALL] Running cmake --install (windeployqt)...")
    echo()

    install_cmd = [
        "cmake", "--install", str(build_dir),
        "--config", build_type,
    ]
    result = subprocess.run(install_cmd, env=env)

    if result.returncode != 0:
        echo()
        echo("[ERROR] cmake --install failed.")
        return 1

    # Report results
    staging = build_dir / "staging"
    exe = staging / "bin" / "QGroundControl.exe"
    echo()
    echo("=" * 68)
    echo(" DEPLOY COMPLETE")
    echo("=" * 68)
    if exe.exists():
        for root, dirs, files in os.walk(staging):
            dll_count = sum(1 for f in files if f.endswith(".dll"))
        echo(f"  Staging dir : {staging}")
        echo(f"  Executable  : {exe}")
        echo(f"  DLLs        : {dll_count}")
        echo()
        echo("  To run on another PC:")
        echo(f"    1. Copy this folder: {staging}")
        echo(f"    2. On target PC, install VC++ Redist:")
        echo(f"       {staging}\\bin\\vc_redist.x64.exe")
        echo(f"    3. Run: bin\\QGroundControl.exe")
        echo()
        # Check for installer
        installer = next(build_dir.glob("QGroundControl-installer-*.exe"), None)
        if installer:
            echo(f"  Installer: {installer}")
        else:
            echo("  (No installer generated — NSIS (makensis) not found)")
    else:
        echo(f"  (Staging dir: {staging})")
        echo("  NOTE: QGroundControl.exe not found in staging/bin.")
        echo("        Check cmake --install output above for errors.")

    return 0


# ============================================================================
# Main
# ============================================================================

def main() -> int:
    action = sys.argv[1] if len(sys.argv) > 1 else "all"

    # deploy defaults to Release + build_release (unless overridden via env)
    if action == "deploy":
        build_type = os.environ.get("BUILD_TYPE", "Release")
        build_dir_name = os.environ.get("BUILD_DIR", "build_release")
    else:
        build_type = os.environ.get("BUILD_TYPE", "Debug")
        build_dir_name = os.environ.get("BUILD_DIR", "build")

    build_dir = SCRIPT_DIR / build_dir_name
    jobs = int(os.environ.get("JOBS", str(max(os.cpu_count() - 1, 1))))

    echo("=" * 68)
    echo(" QGroundControl Build Script")
    echo("=" * 68)
    echo(f"  Action:     {action}")
    echo(f"  Build Type: {build_type}")
    echo(f"  Build Dir:  {build_dir}")
    echo(f"  Jobs:       {jobs}")
    echo("=" * 68)
    echo()

    # Validate action
    valid_actions = {"all", "configure", "build", "run", "rebuild", "clean", "deploy"}
    if action not in valid_actions:
        echo(f"[ERROR] Unknown action: {action}")
        echo(f"        Valid actions: {', '.join(sorted(valid_actions))}")
        return 1

    # Clean doesn't need Qt or MSVC
    if action == "clean":
        return do_clean(build_dir)

    # Step 1: Detect Qt
    echo("[1/4] Detecting Qt...")
    qt_root, qt_version = detect_qt()
    if qt_root is None:
        echo("[ERROR] Qt6 not found under C:\\Qt.")
        echo("        Install Qt 6.11.x (preferred) with msvc2022_64 kit,")
        echo("        or set QT_ROOT_DIR environment variable:")
        echo("          set QT_ROOT_DIR=C:\\Qt\\6.10.1\\msvc2022_64")
        return 1

    qt_cmake = qt_root / "bin" / "qt-cmake.bat"
    echo(f"      QT_ROOT_DIR: {qt_root}")
    echo(f"      qt-cmake:    {qt_cmake}")
    echo(f"      version:     {qt_version}")
    echo()

    # Step 2: Qt version range
    qt_ver_min, qt_ver_max = get_qt_version_range(qt_version or "6.10.0")
    echo(f"[2/4] Qt version range: {qt_ver_min} ... {qt_ver_max}")
    echo(f"      (overriding project requirement of 6.11.0 ... 6.11.1)")
    echo()

    # Step 3: MSVC environment
    echo("[3/4] Setting up MSVC environment...")
    vs_path = detect_vs()
    if vs_path is None:
        echo("[ERROR] Visual Studio 2022 not found.")
        echo("        Install VS2022 with 'Desktop development with C++' workload,")
        echo("        or set VS_PATH environment variable.")
        return 1

    msvc_env = setup_msvc_env(vs_path)
    echo("      MSVC environment initialized.")
    echo()

    # Step 4: Execute action
    if action == "configure":
        return do_configure(qt_root, qt_cmake, qt_ver_min, qt_ver_max,
                            build_type, build_dir, msvc_env)

    if action == "build":
        return do_build(build_dir, build_type, jobs, msvc_env)

    if action == "run":
        return do_run(build_dir, build_type, qt_root)

    if action == "rebuild":
        do_clean(build_dir)
        rc = do_configure(qt_root, qt_cmake, qt_ver_min, qt_ver_max,
                          build_type, build_dir, msvc_env)
        if rc != 0:
            return rc
        return do_build(build_dir, build_type, jobs, msvc_env)

    if action == "deploy":
        return do_deploy(qt_root, qt_cmake, qt_ver_min, qt_ver_max,
                         build_type, build_dir, jobs, msvc_env)

    # action == "all"
    rc = do_configure(qt_root, qt_cmake, qt_ver_min, qt_ver_max,
                      build_type, build_dir, msvc_env)
    if rc != 0:
        return rc
    rc = do_build(build_dir, build_type, jobs, msvc_env)
    if rc != 0:
        return rc
    return do_run(build_dir, build_type, qt_root)


if __name__ == "__main__":
    sys.exit(main())
