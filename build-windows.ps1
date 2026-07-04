<#
.SYNOPSIS
    QGroundControl Windows Build Script
.DESCRIPTION
    Auto-detect environment, configure and build QGroundControl for Windows.
    Supports Release/Debug build, packaging installer.
.PARAMETER BuildType
    Build type: Release or Debug (default: Release)
.PARAMETER CleanBuild
    Clean build directory before building
.PARAMETER Package
    Generate installer after build (requires NSIS)
.PARAMETER Jobs
    Number of parallel build jobs (default: CPU core count)
.PARAMETER QtPath
    Qt installation path (auto-detect if not specified)
.PARAMETER Force
    Skip interactive prompts (auto-continue on warnings)
.NOTES
    Version: 1.2
    Date: 2026-07-04
#>

[CmdletBinding()]
param(
    [ValidateSet("Release", "Debug")]
    [string]$BuildType = "Release",

    [switch]$CleanBuild,

    [switch]$Package,

    [int]$Jobs = 0,

    [string]$QtPath = "",

    [switch]$Force
)

$ErrorActionPreference = "Continue"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = $ScriptDir
$BuildDir = Join-Path $ProjectRoot "build\qt6-Windows"
$StagingDir = Join-Path $BuildDir "staging"

if ($Jobs -le 0) {
    $Jobs = $env:NUMBER_OF_PROCESSORS
}

# Color output helpers
function Write-Step {
    param([string]$Text)
    Write-Host ""
    Write-Host ("=" * 70) -ForegroundColor Cyan
    Write-Host "  $Text" -ForegroundColor Cyan
    Write-Host ("=" * 70) -ForegroundColor Cyan
}
function Write-OK  { param([string]$T)  Write-Host "  [OK] $T" -ForegroundColor Green }
function Write-Warn { param([string]$T) Write-Host "  [!!] $T" -ForegroundColor Yellow }
function Write-Fail { param([string]$T) Write-Host "  [FAIL] $T" -ForegroundColor Red }
function Write-Info { param([string]$T) Write-Host "  [..] $T" -ForegroundColor Gray }

# ============================================================================
# Step 1: Environment Detection
# ============================================================================
Write-Step "Step 1/6: Detect Build Environment"

# --- Detect Visual Studio 2022 ---
Write-Info "Detecting Visual Studio 2022..."

$VsPath = $null
$VsEdition = ""

$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (Test-Path $vswhere) {
    $vsInfo = & $vswhere -latest -products * -requires Microsoft.Component.MSBuild -property installationPath 2>$null
    if ($vsInfo) {
        $VsPath = $vsInfo
        if ($VsPath -match "Community")        { $VsEdition = "Community" }
        elseif ($VsPath -match "Professional") { $VsEdition = "Professional" }
        elseif ($VsPath -match "Enterprise")   { $VsEdition = "Enterprise" }
        elseif ($VsPath -match "BuildTools")   { $VsEdition = "BuildTools" }
    }
}

if (-not $VsPath) {
    $possiblePaths = @(
        "${env:ProgramFiles}\Microsoft Visual Studio\2022\Community",
        "${env:ProgramFiles}\Microsoft Visual Studio\2022\Professional",
        "${env:ProgramFiles}\Microsoft Visual Studio\2022\Enterprise",
        "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2022\BuildTools"
    )
    foreach ($p in $possiblePaths) {
        if (Test-Path $p) { $VsPath = $p; $VsEdition = Split-Path $p -Leaf; break }
    }
}

if (-not $VsPath) {
    Write-Fail "Visual Studio 2022 not found!"
    Write-Host "  Please install Visual Studio 2022 with C++ Desktop Development workload."
    Write-Host "  Download: https://visualstudio.microsoft.com/downloads/"
    exit 1
}

$VsVarsBat = Join-Path $VsPath "VC\Auxiliary\Build\vcvars64.bat"
if (-not (Test-Path $VsVarsBat)) {
    Write-Fail "vcvars64.bat not found: $VsVarsBat"
    exit 1
}
Write-OK "Visual Studio 2022 $VsEdition"
Write-Info "  Path: $VsPath"

# --- Detect Ninja ---
Write-Info "Detecting Ninja..."

$NinjaExe = $null

# Prefer Ninja from VS installation (more reliable than PATH/WinGet)
$vsNinja = Join-Path $VsPath "Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja\ninja.exe"
if (Test-Path $vsNinja) {
    $NinjaExe = $vsNinja
    $ninjaDir = Split-Path $NinjaExe -Parent
    # Prepend to PATH so VS ninja takes priority
    $env:PATH = "$ninjaDir;$env:PATH"
}

# Also check PATH
if (-not $NinjaExe) {
    $ninjaCmd = Get-Command ninja -ErrorAction SilentlyContinue
    if ($ninjaCmd) {
        # Verify it's not the broken WinGet shim
        $testResult = & $ninjaCmd.Source --version 2>&1
        if ($LASTEXITCODE -eq 0) {
            $NinjaExe = $ninjaCmd.Source
        } else {
            Write-Warn "Found broken Ninja at $($ninjaCmd.Source), ignoring"
        }
    }
}

if ($NinjaExe) {
    $ninjaVer = (& $NinjaExe --version 2>&1) -replace "`n|`r", ""
    Write-OK "Ninja $ninjaVer"
    Write-Info "  Path: $NinjaExe"
} else {
    Write-Warn "Ninja not found, will try CMake default generator"
}

# --- Detect CMake ---
Write-Info "Detecting CMake..."
$cmakeCmd = Get-Command cmake -ErrorAction SilentlyContinue
if (-not $cmakeCmd) {
    Write-Fail "CMake not found! Please install CMake >= 3.25"
    Write-Host "  Download: https://cmake.org/download/"
    exit 1
}
$cmakeVer = (& cmake --version 2>$null | Select-Object -First 1)
Write-OK $cmakeVer
Write-Info "  Path: $($cmakeCmd.Source)"

# --- Detect Qt 6.8.3 ---
Write-Info "Detecting Qt 6.8.3..."

if ($QtPath -and (Test-Path $QtPath)) {
    $cfg = Join-Path $QtPath "bin\qt-cmake.bat"
    if (-not (Test-Path $cfg)) { $QtPath = "" }
}

if (-not $QtPath -and $env:QT_ROOT_DIR) {
    $cfg = Join-Path $env:QT_ROOT_DIR "bin\qt-cmake.bat"
    if (Test-Path $cfg) { $QtPath = $env:QT_ROOT_DIR }
}

if (-not $QtPath -and $env:CMAKE_PREFIX_PATH) {
    $cfg = Join-Path $env:CMAKE_PREFIX_PATH "bin\qt-cmake.bat"
    if (Test-Path $cfg) { $QtPath = $env:CMAKE_PREFIX_PATH }
}

if (-not $QtPath) {
    $searchPaths = @(
        "C:\Qt\6.8.3\msvc2022_64",
        "D:\Qt\6.8.3\msvc2022_64",
        "E:\Qt\6.8.3\msvc2022_64",
        "C:\Qt\6.8.3\msvc2022",
        "C:\Qt\6.8.2\msvc2022_64",
        "C:\Qt\6.8.1\msvc2022_64",
        "C:\Qt\6.8.0\msvc2022_64"
    )
    foreach ($p in $searchPaths) {
        $cfg = Join-Path $p "bin\qt-cmake.bat"
        if (Test-Path $cfg) { $QtPath = $p; break }
    }
}

if (-not $QtPath) {
    # Search C:\Qt for any Qt6 msvc installation
    $qtRoot = "C:\Qt"
    if (Test-Path $qtRoot) {
        $foundDirs = Get-ChildItem $qtRoot -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match "^6\.\d" } |
            Sort-Object Name -Descending
        foreach ($d in $foundDirs) {
            $msvcDirs = Get-ChildItem $d.FullName -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match "msvc2022" } |
                Sort-Object Name -Descending
            foreach ($m in $msvcDirs) {
                $cfg = Join-Path $m.FullName "bin\qt-cmake.bat"
                if (Test-Path $cfg) { $QtPath = $m.FullName; break }
            }
            if ($QtPath) { break }
        }
    }
}

if (-not $QtPath) {
    Write-Fail "Qt 6.8.3 (msvc2022_64) not found!"
    Write-Host ""
    Write-Host "  Please install Qt 6.8.3 using one of these methods:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Method 1 - Qt Online Installer:" -ForegroundColor White
    Write-Host "    1. Download: https://www.qt.io/download-qt-installer"
    Write-Host "    2. Select: Qt 6.8.3 -> MSVC 2022 64-bit"
    Write-Host "    3. Extra modules: qtcharts, qtlocation, qtpositioning,"
    Write-Host "       qtspeech, qt5compat, qtmultimedia, qtserialport,"
    Write-Host "       qtimageformats, qtshadertools, qtconnectivity,"
    Write-Host "       qtquick3d, qtsensors"
    Write-Host ""
    Write-Host "  Method 2 - aqtinstall (requires Python):" -ForegroundColor White
    Write-Host "    pip install aqtinstall"
    Write-Host "    aqt install-qt windows desktop 6.8.3 win64_msvc2022_64 -O C:\Qt -m qtcharts qtlocation qtpositioning qtspeech qt5compat qtmultimedia qtserialport qtimageformats qtshadertools qtconnectivity qtquick3d qtsensors"
    Write-Host ""
    Write-Host "  After installation, specify path with:" -ForegroundColor Yellow
    Write-Host "    .\build-windows.ps1 -QtPath C:\Qt\6.8.3\msvc2022_64"
    Write-Host ""
    exit 1
}

Write-OK "Qt 6.8.3 (msvc2022_64)"
Write-Info "  Path: $QtPath"

if (-not (Test-Path (Join-Path $QtPath "bin\Qt6Core.dll"))) {
    Write-Fail "Qt installation appears incomplete (Qt6Core.dll not found)"
    exit 1
}

# --- Detect GStreamer (optional) ---
Write-Info "Detecting GStreamer..."

$script:gstFound = $false
$script:gstPath = $null

$gstPaths = @(
    $env:GSTREAMER_1_0_ROOT_MSVC_X86_64,
    "C:\gstreamer\1.0\msvc_x86_64",
    "C:\Program Files\gstreamer\1.0\msvc_x86_64"
)
foreach ($gp in $gstPaths) {
    if ($gp) {
        $gstExe = Join-Path $gp "bin\gst-launch-1.0.exe"
        if (Test-Path $gstExe) {
            Write-OK "GStreamer: $gp"
            $env:GSTREAMER_1_0_ROOT_MSVC_X86_64 = $gp
            $script:gstFound = $true
            $script:gstPath = $gp
            break
        }
    }
}
if (-not $script:gstFound) {
    Write-Warn "GStreamer not found (video streaming will be disabled)"
    Write-Info "  Install GStreamer 1.22.12 MSVC x86_64 to enable video streaming"
}

# --- Detect NSIS (only when packaging) ---
if ($Package) {
    Write-Info "Detecting NSIS..."
    $nsisFound = (Get-Command makensis -ErrorAction SilentlyContinue) -ne $null
    if (-not $nsisFound) {
        $nsisPaths = @(
            "C:\Program Files (x86)\NSIS\makensis.exe",
            "C:\Program Files\NSIS\makensis.exe"
        )
        foreach ($np in $nsisPaths) {
            if (Test-Path $np) { $nsisFound = $true; break }
        }
    }
    if (-not $nsisFound) {
        Write-Fail "NSIS not found! Install NSIS or remove -Package flag."
        Write-Host "  Download: https://nsis.sourceforge.io/Download"
        exit 1
    }
    Write-OK "NSIS found"
}

# ============================================================================
# Step 2: Verify MSVC Environment
# ============================================================================
Write-Step "Step 2/6: Verify MSVC Build Environment"

# Validate that vcvars64.bat + MSVC compiler work
$verifyBat = Join-Path $env:TEMP "qgc_verify_msvc.bat"
@"
@echo off
call "$VsVarsBat" >nul
where cl >nul 2>&1
if %ERRORLEVEL% NEQ 0 exit /b 1
cl 2>&1 | findstr /C:"Microsoft"
"@ | Out-File -FilePath $verifyBat -Encoding ASCII -Force

$verifyResult = cmd /c $verifyBat 2>&1
Remove-Item $verifyBat -Force -ErrorAction SilentlyContinue

if ($LASTEXITCODE -ne 0) {
    Write-Fail "MSVC compiler not available via vcvars64.bat"
    exit 1
}
Write-OK "MSVC compiler verified"
$clVersion = ($verifyResult | Select-String "Microsoft" | Select-Object -First 1).ToString().Trim()
Write-Info "  $clVersion"

# ============================================================================
# Step 2b: Check Git and Network Connectivity
# ============================================================================
Write-Info "Checking Git and network connectivity..."

$gitCmd = Get-Command git -ErrorAction SilentlyContinue
if (-not $gitCmd) {
    Write-Fail "Git not found! Git is required to clone build dependencies."
    Write-Host "  Download: https://git-scm.com/download/win"
    exit 1
}
Write-OK "Git: $($gitCmd.Source)"

Write-Info "Testing GitHub connectivity..."
$proxyConfig = (& git config --global http.proxy 2>$null) -replace "`n|`r", ""
if ($proxyConfig) {
    Write-Info "Git proxy configured: $proxyConfig"
}

# Quick connectivity test
$githubReachable = $false
try {
    $req = [System.Net.WebRequest]::Create("https://github.com")
    $req.Timeout = 10000
    $resp = $req.GetResponse()
    $resp.Close()
    $githubReachable = $true
} catch {
    # Try with TLS
    try {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12 -bor [System.Net.SecurityProtocolType]::Tls13
        $req = [System.Net.WebRequest]::Create("https://github.com")
        $req.Timeout = 10000
        $resp = $req.GetResponse()
        $resp.Close()
        $githubReachable = $true
    } catch {}
}

if (-not $githubReachable) {
    Write-Warn "GitHub is not reachable!"
    Write-Host ""
    Write-Host "  QGC build requires downloading dependencies from GitHub." -ForegroundColor Yellow
    Write-Host "  This build will likely fail due to network issues." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Possible solutions:" -ForegroundColor White
    Write-Host "    1. Ensure internet connectivity and try again"
    Write-Host "    2. Configure a Git proxy if needed:"
    Write-Host "       git config --global http.proxy http://your-proxy:port"
    Write-Host "    3. Use QGC_CPM_SOURCE_CACHE to pre-seed dependencies"
    Write-Host ""
    if (-not $Force) {
        Write-Host "  Continue anyway? (y/N)" -NoNewline -ForegroundColor Yellow
        $choice = Read-Host
        if ($choice -notmatch '^[yY]') {
            Write-Fail "Build aborted by user"
            exit 1
        }
    } else {
        Write-Warn "Continuing despite connectivity issues (Force mode)..."
    }
} else {
    Write-OK "GitHub reachable"
}

# ============================================================================
# Helper: Run CMake via CMD with vcvars environment
# ============================================================================
function Invoke-CMakeWithMSVC {
    param(
        [string[]]$Cmds,
        [string]$WorkingDir = $ProjectRoot
    )

    # Build the cmake command line (escape special chars for batch file)
    $cmakeCmdLine = ""
    foreach ($c in $Cmds) {
        if ($c -match '[\s]') {
            $cmakeCmdLine += "`"$c`" "
        } else {
            $cmakeCmdLine += "$c "
        }
    }
    $cmakeCmdLine = $cmakeCmdLine.TrimEnd()

    # Write a temporary batch file with vcvars + cmake command embedded
    $tempBat = Join-Path $env:TEMP "qgc_cmake_run.bat"
    $batContent = @"
@echo off
call "$VsVarsBat" >nul 2>&1
set QT_ROOT_DIR=$QtPath
set CMAKE_PREFIX_PATH=$QtPath
set PATH=$QtPath\bin;%PATH%
cmake $cmakeCmdLine
"@
    $batContent | Out-File -FilePath $tempBat -Encoding ASCII -Force

    $prevExitCode = $global:LASTEXITCODE
    $rawOutput = cmd /c $tempBat 2>&1 | ForEach-Object {
        $line = "$_"
        # Filter out PowerShell RemoteException noise from cmd stderr
        if ($line -match '^System\.Management\.Automation\.RemoteException$|^\s*$') {
            return
        }
        $line
    } | Where-Object { $_ -ne $null }
    $exitCode = $global:LASTEXITCODE

    Remove-Item $tempBat -Force -ErrorAction SilentlyContinue
    return @{ ExitCode = $exitCode; Output = $rawOutput }
}

# ============================================================================
# Step 3: CMake Configure
# ============================================================================
Write-Step "Step 3/6: CMake Configure"

$useNinja = (Get-Command ninja -ErrorAction SilentlyContinue) -ne $null

if ($useNinja) {
    $generator = "Ninja Multi-Config"
    Write-Info "Generator: Ninja Multi-Config"
} else {
    $generator = "Visual Studio 17 2022"
    Write-Info "Generator: Visual Studio 17 2022 (Ninja not available)"
}

$qtToolchain = Join-Path $QtPath "lib\cmake\Qt6\qt.toolchain.cmake"

$configArgs = @(
    "-S", $ProjectRoot,
    "-B", $BuildDir,
    "-G", $generator
)

if ($useNinja) {
    if (Test-Path $qtToolchain) {
        $configArgs += "-DCMAKE_TOOLCHAIN_FILE=$qtToolchain"
        Write-Info "Qt toolchain: $qtToolchain"
    }
    $configArgs += "-DCMAKE_CONFIGURATION_TYPES=Release;Debug"
} else {
    $configArgs += "-A"
    $configArgs += "x64"
}

$configArgs += "-DCMAKE_PREFIX_PATH=$QtPath"
$configArgs += "-DQGC_STABLE_BUILD=OFF"
$configArgs += "-DQGC_BUILD_TESTING=OFF"

# Set GStreamer path if found, required for video streaming support
if ($script:gstFound -and $script:gstPath) {
    $configArgs += "-DGSTREAMER_ROOT=$($script:gstPath)"
    Write-Info "GStreamer path configured: $($script:gstPath)"
}

# Clean build directory if requested
if ($CleanBuild -and (Test-Path $BuildDir)) {
    Write-Info "Cleaning build directory: $BuildDir"
    Remove-Item -Recurse -Force $BuildDir -ErrorAction SilentlyContinue
    Write-OK "Build directory cleaned"
}

Write-Info "Running CMake configure..."
Write-Host "  > cmake $($configArgs -join ' ')" -ForegroundColor DarkGray

$result = Invoke-CMakeWithMSVC -Cmds $configArgs

# Print output
$result.Output | ForEach-Object { Write-Host $_ }

if ($result.ExitCode -ne 0) {
    Write-Fail "CMake configure failed! Exit code: $($result.ExitCode)"
    Write-Host ""

    # Check for common error patterns and give targeted advice
    $errorLines = $result.Output -join "`n"

    if ($errorLines -match "fatal: unable to access|Failed to connect to|Could not connect") {
        Write-Host "  >> Network Error Detected <<" -ForegroundColor Yellow
        Write-Host "  Cannot download build dependencies from remote repositories." -ForegroundColor Yellow
        Write-Host "  Check your internet connection or Git proxy settings:" -ForegroundColor Yellow
        Write-Host "    git config --global http.proxy http://proxy:port" -ForegroundColor White
    }
    elseif ($errorLines -match "Could NOT find.*Qt6") {
        Write-Host "  >> Qt Module Missing <<" -ForegroundColor Yellow
        Write-Host "  Ensure all required Qt modules are installed:" -ForegroundColor Yellow
        Write-Host "    qtcharts, qtlocation, qtpositioning, qtspeech, qt5compat," -ForegroundColor White
        Write-Host "    qtmultimedia, qtserialport, qtimageformats, qtshadertools," -ForegroundColor White
        Write-Host "    qtconnectivity, qtquick3d, qtsensors" -ForegroundColor White
    }
    elseif ($errorLines -match "(?i)Could (NOT find|not locate).*GStreamer" -and $errorLines.Count -le 10) {
        Write-Host "  >> GStreamer Missing <<" -ForegroundColor Yellow
        Write-Host "  Install GStreamer 1.22.12 MSVC x86_64 or run:" -ForegroundColor Yellow
        Write-Host "    .\tools\setup\install-dependencies-windows.ps1" -ForegroundColor White
    }
    elseif ($errorLines -match "(?i)Could (NOT find|not locate).*Qt5Compat") {
        Write-Host "  >> Qt5Compat Module Missing <<" -ForegroundColor Yellow
        Write-Host "  Install the Qt 5 Compatibility module (qt5compat)." -ForegroundColor Yellow
    }
    elseif ($errorLines -match "Configuring incomplete") {
        Write-Host "  >> Configuration Error <<" -ForegroundColor Yellow
        Write-Host "  Scroll up to see the actual error above this message." -ForegroundColor Yellow
        Write-Host "  Common causes: missing Qt modules, network issues, or incompatible toolchain." -ForegroundColor Yellow
    }

    Write-Host ""
    exit $result.ExitCode
}

Write-OK "CMake configure successful"
Write-Info "Build directory: $BuildDir"

# ============================================================================
# Step 4: Build
# ============================================================================
Write-Step "Step 4/6: Build QGroundControl [$BuildType]"

$buildArgs = @(
    "--build", $BuildDir,
    "--config", $BuildType
)

if ($Jobs -gt 0) {
    $buildArgs += "--parallel"
    $buildArgs += $Jobs
}

Write-Info "Starting build (parallel jobs: $Jobs)..."
Write-Host "  > cmake $($buildArgs -join ' ')" -ForegroundColor DarkGray

$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

$result = Invoke-CMakeWithMSVC -Cmds $buildArgs

# Print output (live-like, only showing key lines to avoid flooding)
$result.Output | ForEach-Object { Write-Host $_ }

$stopwatch.Stop()
$elapsed = $stopwatch.Elapsed
$buildTime = "{0:D2}:{1:D2}:{2:D2}" -f $elapsed.Hours, $elapsed.Minutes, $elapsed.Seconds

if ($result.ExitCode -ne 0) {
    Write-Fail "Build failed! Time: $buildTime"
    exit $result.ExitCode
}

Write-OK "Build successful! Time: $buildTime"

# Show output artifact
$exePath = Join-Path $BuildDir "$BuildType\QGroundControl.exe"
if (Test-Path $exePath) {
    $exeFile = Get-Item $exePath
    $exeSize = "{0:N2} MB" -f ($exeFile.Length / 1MB)
    Write-OK "Executable: $exePath ($exeSize)"
} else {
    Write-Warn "Executable not found at expected path: $exePath"
    Write-Info "Searching for executable in build directory..."
    Get-ChildItem $BuildDir -Recurse -Filter "QGroundControl.exe" -ErrorAction SilentlyContinue |
        ForEach-Object { Write-Info "Found: $($_.FullName)" }
}

# ============================================================================
# Step 5: Deploy Runtime Dependencies
# ============================================================================
Write-Step "Step 5/6: Deploy Runtime Dependencies"

$exeDir = Join-Path $BuildDir $BuildType
$exeFile = Join-Path $exeDir "QGroundControl.exe"

if (-not (Test-Path $exeFile)) {
    Write-Warn "Executable not found, skipping deployment"
} else {
    # 5a. Run windeployqt for Qt DLLs, plugins, QML modules
    $qtBinDir = Join-Path $QtPath "bin"
    $windeployqt = Join-Path $qtBinDir "windeployqt.exe"
    if (Test-Path $windeployqt) {
        Write-Info "Running windeployqt..."
        $qmlSourceDir = Join-Path $ProjectRoot "src"
        & $windeployqt --release --qmldir $qmlSourceDir $exeFile 2>&1 | ForEach-Object {
            $line = "$_"
            if ($line -match '^\s*$|RemoteException') { return }
            if ($line -match "Warning|warning" -and $line -match "dxcompiler|dxil|VCINSTALLDIR") { return }
            Write-Host "    $line" -ForegroundColor DarkGray
        }
        if ($LASTEXITCODE -eq 0) {
            Write-OK "Qt runtime deployed (windeployqt)"
        } else {
            Write-Warn "windeployqt completed with warnings"
        }
    } else {
        Write-Warn "windeployqt not found at $windeployqt"
    }

    # 5b. Copy GStreamer DLLs and plugins
    if ($script:gstFound -and $script:gstPath) {
        Write-Info "Deploying GStreamer runtime..."
        $gstBinDir = Join-Path $script:gstPath "bin"
        $gstLibDir = Join-Path $script:gstPath "lib"
        $gstPluginDir = Join-Path $gstLibDir "gstreamer-1.0"

        # Copy ALL DLLs from GStreamer bin (some plugins need them at runtime)
        Copy-Item (Join-Path $gstBinDir "*.dll") $exeDir -Force -ErrorAction SilentlyContinue
        $dllCount = (Get-ChildItem $exeDir -Filter "*.dll").Count

        # Copy GStreamer plugins
        if (Test-Path $gstPluginDir) {
            $pluginDest = Join-Path $exeDir "gstreamer-1.0"
            if (-not (Test-Path $pluginDest)) {
                New-Item -ItemType Directory -Path $pluginDest -Force | Out-Null
            }
            Copy-Item (Join-Path $gstPluginDir "*.dll") $pluginDest -Force -ErrorAction SilentlyContinue
            $pluginCount = (Get-ChildItem $pluginDest -Filter "*.dll").Count
            Write-OK "GStreamer deployed ($dllCount DLLs, $pluginCount plugins)"
        } else {
            Write-OK "GStreamer DLLs deployed ($dllCount DLLs)"
        }
    } else {
        Write-Warn "GStreamer not found, video streaming will not work at runtime"
    }

    # 5c. Set up GST_PLUGIN_PATH for runtime
    $pluginRelDir = Join-Path $exeDir "gstreamer-1.0"
    if (Test-Path $pluginRelDir) {
        $env:GST_PLUGIN_PATH = $pluginRelDir
        Write-Info "GST_PLUGIN_PATH configured"
    }

    Write-OK "Runtime deployment complete"
}

# ============================================================================
# Step 6: Package Installer (optional)
# ============================================================================
if ($Package) {
    Write-Step "Step 6/6: Package Installer"

    Write-Info "Deploying Qt runtime dependencies..."
    $installArgs = @(
        "--install", $BuildDir,
        "--config", $BuildType,
        "--prefix", $StagingDir
    )
    $result = Invoke-CMakeWithMSVC -Cmds $installArgs
    if ($result.ExitCode -ne 0) {
        Write-Fail "Deployment failed!"
        $result.Output | ForEach-Object { Write-Host $_ }
        exit $result.ExitCode
    }
    Write-OK "Deployment complete: $StagingDir"

    Write-Info "Generating installer..."
    $pkgArgs = @("--build", $BuildDir, "--config", $BuildType, "--target", "package")
    $result = Invoke-CMakeWithMSVC -Cmds $pkgArgs
    if ($result.ExitCode -eq 0) {
        $installerFiles = @(Get-ChildItem $BuildDir -Filter "*installer*.exe" -ErrorAction SilentlyContinue)
        if ($installerFiles.Count -eq 0) {
            $installerFiles = @(Get-ChildItem $BuildDir -Filter "QGroundControl*.exe" -ErrorAction SilentlyContinue)
        }
        if ($installerFiles.Count -gt 0) {
            Write-OK "Installer generated: $($installerFiles[0].FullName)"
        }
    } else {
        Write-Warn "Installer generation failed, but build artifacts are available."
        Write-Info "You may need to install NSIS or check packaging configuration."
    }
} else {
    Write-Info "Packaging skipped (use -Package to generate installer)"
}

# ============================================================================
# Complete
# ============================================================================
Write-Host ""
Write-Host ("=" * 70) -ForegroundColor Green
Write-Host "  Build Complete!" -ForegroundColor Green
Write-Host ("=" * 70) -ForegroundColor Green
Write-Host ""
Write-Host "  Executable : " -NoNewline
Write-Host "$BuildDir\$BuildType\QGroundControl.exe" -ForegroundColor Yellow
Write-Host "  Build type : " -NoNewline
Write-Host $BuildType -ForegroundColor Yellow
Write-Host "  Build dir  : " -NoNewline
Write-Host $BuildDir -ForegroundColor Yellow
Write-Host ""
Write-Host "  To run the program:" -ForegroundColor Gray
Write-Host "    .\$BuildDir\$BuildType\QGroundControl.exe" -ForegroundColor White
Write-Host ""
