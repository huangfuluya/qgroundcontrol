# ==============================================================================
# Mingw-w64 x86_64 Cross-Compilation Toolchain for Windows Target
# ==============================================================================
#
# Usage:
#   cmake -S <src> -B <build> -G Ninja \
#         -DCMAKE_TOOLCHAIN_FILE=cmake/toolchains/mingw-w64-x86_64.cmake \
#         -DQT_HOST_PATH=/path/to/linux/qt \
#         -DCMAKE_PREFIX_PATH=/path/to/windows/mingw/qt
#

set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_PROCESSOR x86_64)

# ---- Cross-Compiler Binaries ----
set(CMAKE_C_COMPILER    x86_64-w64-mingw32-gcc-posix)
set(CMAKE_CXX_COMPILER  x86_64-w64-mingw32-g++-posix)
set(CMAKE_RC_COMPILER   x86_64-w64-mingw32-windres)
set(CMAKE_AR            x86_64-w64-mingw32-ar    CACHE FILEPATH "Archiver")
set(CMAKE_RANLIB        x86_64-w64-mingw32-ranlib CACHE FILEPATH "Ranlib")
set(CMAKE_STRIP         x86_64-w64-mingw32-strip  CACHE FILEPATH "Strip")

# ---- Root Path: use BOTH so Qt6 find_package works through CMAKE_PREFIX_PATH ----
# (ONLY mode would restrict all searches to CMAKE_FIND_ROOT_PATH, breaking Qt detection)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY BOTH)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE BOTH)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE BOTH)

# ---- Compiler / Linker Flags ----
set(CMAKE_C_FLAGS_INIT   "-static-libgcc")
set(CMAKE_CXX_FLAGS_INIT "-static-libgcc -static-libstdc++")

# ---- Disable host-only features ----
set(QGC_USE_CACHE OFF CACHE BOOL "Disable sccache/ccache for cross-compilation")
