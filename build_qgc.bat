@echo off
rem ============================================================================
rem QGroundControl Build & Launch - wrapper for build_qgc.py
rem Usage:
rem   build_qgc.bat            - Configure + Build + Run
rem   build_qgc.bat configure  - Only configure CMake
rem   build_qgc.bat build      - Only build
rem   build_qgc.bat run        - Only launch QGC
rem   build_qgc.bat rebuild    - Clean + Configure + Build
rem   build_qgc.bat clean      - Clean build directory
rem   build_qgc.bat deploy     - Configure + Build + Install (windeployqt, for distribution)
rem ============================================================================
rem Qt 6.11 initDebuggingConsole triggers Q_ASSERT(in == stdin) when launched
rem via "start" from a cmd shell (no inherited stdout handle). Setting a value
rem other than "new"/"attach" lets both QGC and Qt skip the debugging-console
rem attach/alloc path, avoiding the crash.
set QT_WIN_DEBUG_CONSOLE=disabled
python "%~dp0build_qgc.py" %*
