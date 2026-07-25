# ============================================================================
# QGroundControl - Build & Run Script (Windows / PowerShell)
# ============================================================================
#
# 用法:
#   .\scripts\build_and_run.ps1                        # 默认: Release 编译 + 运行
#   .\scripts\build_and_run.ps1 -SkipBuild              # 跳过编译，直接运行
#   .\scripts\build_and_run.ps1 -SkipRun                # 仅编译，不运行
#   .\scripts\build_and_run.ps1 -BuildType Debug        # Debug 模式编译 + 运行
#   .\scripts\build_and_run.ps1 -Configure              # 强制重新配置 CMake
#   .\scripts\build_and_run.ps1 -Jobs 8                 # 指定并行编译任务数
#   .\scripts\build_and_run.ps1 -QtRoot "C:\Qt\6.11.1\msvc2022_64"  # 指定 Qt 路径
#
# 首次使用:
#   1. 安装 Qt (版本要求见 .github/build-config.json)
#   2. 安装 Visual Studio 2022 (含 "使用 C++ 的桌面开发" 工作负载)
#   3. (可选) 安装 GStreamer 1.0 MSVC 64-bit 运行时
#   4. 运行: .\scripts\build_and_run.ps1
# ============================================================================

param(
    [ValidateSet("Debug", "Release", "RelWithDebInfo")]
    [string]$BuildType = "Release",

    [switch]$SkipBuild,
    [switch]$SkipRun,
    [switch]$Configure,
    [switch]$InstallQt,

    [int]$Jobs = [Environment]::ProcessorCount,

    [string]$QtRoot = "",
    [string]$BuildDir = "build",
    [string]$GStreamerDir = ""
)

$ErrorActionPreference = "Stop"
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptRoot

# Resolve absolute build directory
if (-not [System.IO.Path]::IsPathRooted($BuildDir)) {
    $BuildDir = Join-Path $ProjectRoot $BuildDir
}

$ExePath = Join-Path (Join-Path $BuildDir $BuildType) "QGroundControl.exe"

# ============================================================================
# 辅助函数
# ============================================================================

function Write-Header {
    param([string]$Text)
    Write-Host "`n================================================" -ForegroundColor Cyan
    Write-Host "  $Text" -ForegroundColor Cyan
    Write-Host "================================================`n" -ForegroundColor Cyan
}

function Write-Step {
    param([string]$Text)
    Write-Host ">>> $Text" -ForegroundColor Yellow
}

function Write-OK {
    param([string]$Text)
    Write-Host "  [OK] $Text" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Text)
    Write-Host "  [WARN] $Text" -ForegroundColor Magenta
}

function Write-ErrorMsg {
    param([string]$Text)
    Write-Host "  [ERROR] $Text" -ForegroundColor Red
}

# 从 vcvars64.bat 获取 MSVC 环境变量
function Get-VsEnvironment {
    $vcvarsPath = "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat"

    if (-not (Test-Path $vcvarsPath)) {
        $editions = @("Professional", "Enterprise", "Community")
        $found = $false
        foreach ($edition in $editions) {
            $vcvarsPath = "C:\Program Files\Microsoft Visual Studio\2022\$edition\VC\Auxiliary\Build\vcvars64.bat"
            if (Test-Path $vcvarsPath) {
                $found = $true
                break
            }
        }
        if (-not $found) {
            Write-ErrorMsg "找不到 Visual Studio 2022。请安装 VS 2022 (含 '使用 C++ 的桌面开发' 工作负载)"
            exit 1
        }
    }

    Write-Step "正在初始化 MSVC 环境 ($vcvarsPath)..."

    $cmdOutput = cmd /c "`"$vcvarsPath`" > NUL 2>&1 && set" 2>&1
    $envHash = @{}

    foreach ($line in $cmdOutput) {
        if ($line -match '^([^=]+)=(.*)$') {
            $envHash[$Matches[1]] = $Matches[2]
        }
    }

    Write-OK "MSVC 环境初始化完成"
    return $envHash
}

# 将环境 hashtable 应用到当前进程
function Apply-Environment {
    param([hashtable]$EnvHash)

    foreach ($key in $EnvHash.Keys) {
        if ($key -in @('_', 'SAFEMODE', 'PROMPT', 'COLOR')) { continue }
        [Environment]::SetEnvironmentVariable($key, $EnvHash[$key], [System.EnvironmentVariableTarget]::Process)
    }
}

# 读取 build-config.json 中的字段
function Get-BuildConfigValue {
    param([string]$KeyPath)

    $configFile = Join-Path $ProjectRoot ".github\build-config.json"
    if (-not (Test-Path $configFile)) {
        return $null
    }

    try {
        $config = Get-Content $configFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $keys = $KeyPath.Split(".")
        $value = $config
        foreach ($key in $keys) {
            $value = $value.$key
        }
        return $value
    } catch {
        return $null
    }
}

# 从 Qt 安装目录提取版本号
function Get-QtVersion {
    param([string]$QtDir)

    $qmake = Join-Path $QtDir "bin\qmake.exe"
    if (-not (Test-Path $qmake)) { return $null }

    # qmake --version 输出两行（例如 "QMake version 3.1" 和 "Using Qt version 6.8.3..."）
    $output = & $qmake --version 2>&1 | Out-String
    if ($output -match 'Qt version (\d+\.\d+\.\d+)') {
        return [Version]$Matches[1]
    }
    return $null
}

# ============================================================================
# 主流程
# ============================================================================

Write-Header "QGroundControl 编译与运行"

# ---------------------------------------------------------------------------
# 1. 检查前置条件
# ---------------------------------------------------------------------------
Write-Step "检查前置条件..."

# CMake
try {
    $cmakeVersion = cmake --version 2>&1 | Select-Object -First 1
    Write-OK "CMake: $cmakeVersion"
} catch {
    Write-ErrorMsg "未找到 CMake，请安装 CMake 3.25+ 并添加到 PATH"
    exit 1
}

# 读取项目要求的 Qt 版本
$requiredQtVer = Get-BuildConfigValue "qt.version"
$requiredQtMinVer = Get-BuildConfigValue "qt.minimum_version"
$requiredQtModules = Get-BuildConfigValue "qt.modules"

if ($requiredQtVer) {
    Write-OK "项目要求 Qt: $requiredQtMinVer ~ $requiredQtVer"
    if ($requiredQtModules) {
        Write-Host "  需要模块: $requiredQtModules" -ForegroundColor DarkGray
    }
} else {
    Write-Warn "无法读取 build-config.json，跳过 Qt 版本检查"
}

# 检测已安装的 Qt
if (-not $QtRoot) {
    # 优先查找项目要求的版本，回退到其他版本
    $qtSearchDirs = @()
    if ($requiredQtVer) {
        $qtSearchDirs += "C:\Qt\$requiredQtVer\msvc2022_64"
    }
    # 回退方案
    $qtSearchDirs += @(
        "C:\Qt\6.11.1\msvc2022_64",
        "C:\Qt\6.11.0\msvc2022_64",
        "C:\Qt\6.10.3\msvc2022_64",
        "C:\Qt\6.10.2\msvc2022_64",
        "C:\Qt\6.8.3\msvc2022_64",
        "C:\Qt\6.8.2\msvc2022_64",
        "C:\Qt\6.8.1\msvc2022_64",
        "C:\Qt\6.8.0\msvc2022_64"
    )
    foreach ($dir in $qtSearchDirs) {
        if (Test-Path (Join-Path $dir "bin\qmake.exe")) {
            $QtRoot = $dir
            break
        }
    }
}

if (-not $QtRoot -or -not (Test-Path (Join-Path $QtRoot "bin\qmake.exe"))) {
    Write-ErrorMsg "未找到 Qt。请安装 Qt $requiredQtMinVer+ (MSVC 2022 64-bit) 或通过 -QtRoot 参数指定路径"
    exit 1
}

$installedQtVer = Get-QtVersion $QtRoot
Write-OK "Qt: $QtRoot (版本: $installedQtVer)"

# Qt 版本兼容性检查
if ($requiredQtMinVer -and $installedQtVer) {
    $minVer = [Version]$requiredQtMinVer
    if ($installedQtVer -lt $minVer) {
        Write-Host ""
        Write-ErrorMsg "Qt 版本不满足要求!"
        Write-Host "  安装的版本: $installedQtVer" -ForegroundColor Red
        Write-Host "  项目要求:   $requiredQtMinVer ~ $requiredQtVer" -ForegroundColor Red
        Write-Host ""

        if ($InstallQt) {
            # 自动安装模式
            Write-Step "自动安装 Qt $requiredQtVer (通过 aqtinstall)..."
            $qtInstallDir = "C:\Qt"
            $aqtArgs = @(
                "install-qt", "windows", "desktop", $requiredQtVer,
                "win64_msvc2022_64",
                "-O", $qtInstallDir,
                "-m", "qtgraphs", "qthttpserver", "qtlocation", "qtpositioning",
                "qtspeech", "qtmultimedia", "qtserialport", "qtimageformats",
                "qtshadertools", "qtconnectivity", "qtquick3d", "qtsensors",
                "qtscxml", "qtwebsockets"
            )

            pip install aqtinstall 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) {
                Write-ErrorMsg "pip install aqtinstall 失败"
                exit 1
            }

            Write-Host "  运行: aqt $($aqtArgs -join ' ')"
            $process = Start-Process -FilePath "aqt" -ArgumentList $aqtArgs -NoNewWindow -Wait -PassThru
            if ($process.ExitCode -ne 0) {
                Write-ErrorMsg "Qt 安装失败 (exit code: $($process.ExitCode))"
                exit $process.ExitCode
            }

            $QtRoot = Join-Path $qtInstallDir $requiredQtVer "msvc2022_64"
            if (Test-Path (Join-Path $BuildDir "CMakeCache.txt")) {
                Write-Step "清理旧的 CMake 缓存..."
                Remove-Item -Path (Join-Path $BuildDir "CMakeCache.txt") -Force -ErrorAction SilentlyContinue
                Remove-Item -Path (Join-Path $BuildDir "CMakeFiles") -Recurse -Force -ErrorAction SilentlyContinue
                Write-OK "已清理"
            }
            $Configure = $true
            $installedQtVer = Get-QtVersion $QtRoot
            Write-OK "Qt 安装完成: $QtRoot (版本: $installedQtVer)"
        } else {
            # 给出修复指引
            Write-Host "  修复方法:" -ForegroundColor Yellow

            $mtPath = "C:\Qt\MaintenanceTool.exe"
            if (Test-Path $mtPath) {
                Write-Host ""
                Write-Host "  方法1 - Qt Maintenance Tool:" -ForegroundColor Yellow
                Write-Host "    运行 Qt Maintenance Tool，添加 Qt $requiredQtVer MSVC 2022 64-bit" -ForegroundColor White
                Write-Host "    以及所需模块 (Qt Graphs, HTTP Server, Location 等)" -ForegroundColor White
            }

            Write-Host ""
            Write-Host "  方法2 - 使用本脚本自动安装:" -ForegroundColor Yellow
            Write-Host "    .\scripts\build_and_run.ps1 -InstallQt" -ForegroundColor White
            Write-Host ""
            Write-Host "  方法3 - 手动使用 aqtinstall:" -ForegroundColor Yellow
            Write-Host "    pip install aqtinstall" -ForegroundColor White
            Write-Host "    aqt install-qt windows desktop $requiredQtVer win64_msvc2022_64 -O C:\Qt \"-m qtgraphs qthttpserver qtlocation qtpositioning qtspeech qtmultimedia qtserialport qtimageformats qtshadertools qtconnectivity qtquick3d qtsensors qtscxml qtwebsockets\"" -ForegroundColor White
            Write-Host ""

            exit 1
        }
    }
}

# 检查 Qt 关键模块是否存在
$missingModules = @()
$requiredModules = @("Graphs", "HttpServer", "Location", "Positioning", "Multimedia", "SerialPort")
foreach ($mod in $requiredModules) {
    $modPath = Join-Path $QtRoot "lib\cmake\Qt6$mod"
    if (-not (Test-Path $modPath)) {
        $missingModules += "Qt6$mod"
    }
}
if ($missingModules.Count -gt 0) {
    Write-Warn "缺少 Qt 模块: $($missingModules -join ', ')"
    Write-Host "  请通过 Qt Maintenance Tool 安装缺失模块后重试" -ForegroundColor Yellow
}

# GStreamer (可选) — 自动检测版本
if (-not $GStreamerDir) {
    $gstCandidates = @(
        "C:\gstreamer\1.0\msvc_x86_64",
        "C:\gstreamer\1.0\x86_64"
    )
    foreach ($candidate in $gstCandidates) {
        if (Test-Path (Join-Path $candidate "bin")) {
            $GStreamerDir = $candidate
            break
        }
    }
}
$hasGStreamer = ($GStreamerDir -and (Test-Path (Join-Path $GStreamerDir "bin")))
$gstVersion = $null
if ($hasGStreamer) {
    $gstPcFile = Join-Path $GStreamerDir "lib\pkgconfig\gstreamer-1.0.pc"
    if (Test-Path $gstPcFile) {
        $pcContent = Get-Content $gstPcFile -Raw
        if ($pcContent -match 'Version:\s*(\S+)') {
            $gstVersion = $Matches[1]
        }
    }
    if ($gstVersion) {
        Write-OK "GStreamer: $GStreamerDir (版本: $gstVersion)"
    } else {
        Write-OK "GStreamer: $GStreamerDir"
    }
} else {
    Write-Host "  [INFO] GStreamer 未找到，视频功能可能不可用" -ForegroundColor DarkYellow
}

# ---------------------------------------------------------------------------
# 2. 编译
# ---------------------------------------------------------------------------
if (-not $SkipBuild) {
    Write-Header "编译 ($BuildType)"

    # 初始化 MSVC 环境
    $vsEnv = Get-VsEnvironment
    Apply-Environment -EnvHash $vsEnv

    # CMake 配置
    $cmakeCachePath = Join-Path $BuildDir "CMakeCache.txt"
    $needConfigure = $Configure -or -not (Test-Path $cmakeCachePath)

    # 检查 CMakeCache 中的 Qt 路径是否与当前一致
    if (-not $needConfigure -and (Test-Path $cmakeCachePath)) {
        $cacheContent = Get-Content $cmakeCachePath -Raw
        $cachedQt6Dir = ""
        if ($cacheContent -match 'Qt6_DIR:PATH=([^\r\n]+)') {
            $cachedQt6Dir = $Matches[1]
            $expectedQt6Dir = Join-Path $QtRoot "lib\cmake\Qt6"
            # 标准化路径比较
            if ((Resolve-Path $cachedQt6Dir -ErrorAction SilentlyContinue).Path -ne
                (Resolve-Path $expectedQt6Dir -ErrorAction SilentlyContinue).Path) {
                Write-Warn "CMake 缓存中的 Qt 路径与当前不一致，将重新配置"
                Write-Host "  缓存: $cachedQt6Dir" -ForegroundColor DarkGray
                Write-Host "  当前: $expectedQt6Dir" -ForegroundColor DarkGray
                Remove-Item $cmakeCachePath -Force -ErrorAction SilentlyContinue
                Remove-Item (Join-Path $BuildDir "CMakeFiles") -Recurse -Force -ErrorAction SilentlyContinue
                $needConfigure = $true
            }
        }
    }

    if ($needConfigure) {
        Write-Step "CMake 配置..."
        $qtToolchain = Join-Path $QtRoot "lib\cmake\Qt6\qt.toolchain.cmake"
        $configureArgs = @(
            "-S", $ProjectRoot,
            "-B", $BuildDir,
            "-G", "Ninja",
            "-DCMAKE_BUILD_TYPE=$BuildType",
            "-DQGC_BUILD_TESTING=OFF",
            "-DCMAKE_PREFIX_PATH=$($QtRoot -replace '\\','/')"
        )

        # qt-cmake (bash 脚本) 在 Windows cmd 下不可靠，使用 cmake + toolchain
        Write-Host "  使用 cmake + Qt toolchain"
        if (Test-Path $qtToolchain) {
            $configureArgs += "-DCMAKE_TOOLCHAIN_FILE=$($qtToolchain -replace '\\','/')"
        }

        # 如果安装了旧版 GStreamer，覆盖版本要求以避免配置失败
        if ($gstVersion) {
            $reqGstVer = Get-BuildConfigValue "gstreamer.version.windows"
            if (-not $reqGstVer) { $reqGstVer = Get-BuildConfigValue "gstreamer.version.default" }
            if ($reqGstVer -and ([Version]$gstVersion -lt [Version]$reqGstVer)) {
                Write-Host "  GStreamer 版本不匹配 (安装: $gstVersion, 要求: $reqGstVer)，使用已安装版本"
                $configureArgs += "-DGStreamer_FIND_VERSION=$gstVersion"
            }
        }

        # 清理上次失败的 GStreamer 自动下载缓存，避免干扰
        $gstCacheDir = Join-Path $ProjectRoot ".cache\CPM\gstreamer-win-x86_64-$reqGstVer"
        if ($reqGstVer -and (Test-Path $gstCacheDir)) {
            $gstSdkDir = Join-Path $gstCacheDir "sdk"
            if (Test-Path $gstSdkDir) {
                # 检查 SDK 是否完整（pkg-config.exe 存在）
                if (-not (Test-Path (Join-Path $gstSdkDir "bin\pkg-config.exe"))) {
                    Remove-Item $gstCacheDir -Recurse -Force -ErrorAction SilentlyContinue
                    Write-Host "  清理失败的 GStreamer 下载缓存"
                }
            }
        }

        Write-Host "  Qt: $QtRoot"
        Write-Host "  构建目录: $BuildDir"

        $process = Start-Process -FilePath "cmake" -ArgumentList $configureArgs -NoNewWindow -Wait -PassThru

        if ($process.ExitCode -ne 0) {
            Write-ErrorMsg "CMake 配置失败 (exit code: $($process.ExitCode))"
            Write-Host ""
            Write-Host "  常见原因:" -ForegroundColor Yellow
            Write-Host "  1. Qt 版本不满足要求 (需要 $requiredQtMinVer+)" -ForegroundColor White
            Write-Host "  2. 缺少 Qt 模块 (如 Qt6Graphs, Qt6HttpServer)" -ForegroundColor White
            Write-Host "  3. MSVC 环境未正确初始化" -ForegroundColor White
            Write-Host ""
            Write-Host "  排查命令:" -ForegroundColor Yellow
            Write-Host "  查看详细日志: cmake -S . -B $BuildDir -G Ninja --debug-find-pkg=Qt6Graphs" -ForegroundColor White
            Write-Host "  检查 Qt 模块: dir $QtRoot\lib\cmake\Qt6*" -ForegroundColor White
            exit $process.ExitCode
        }
        Write-OK "CMake 配置完成"
    } else {
        Write-OK "CMake 已配置，跳过 (使用 -Configure 强制重新配置)"
    }

    # 编译
    Write-Step "开始编译 (并行任务数: $Jobs)..."
    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    $buildArgs = @("--build", $BuildDir, "--config", $BuildType, "--parallel", $Jobs)
    $process = Start-Process -FilePath "cmake" -ArgumentList $buildArgs -NoNewWindow -Wait -PassThru

    $sw.Stop()

    if ($process.ExitCode -ne 0) {
        Write-ErrorMsg "编译失败 (exit code: $($process.ExitCode)，耗时: $([math]::Round($sw.Elapsed.TotalSeconds, 1))s)"
        exit $process.ExitCode
    }

    Write-OK "编译成功! 耗时: $([math]::Round($sw.Elapsed.TotalSeconds, 1))s"
}

# ---------------------------------------------------------------------------
# 3. 运行
# ---------------------------------------------------------------------------
if (-not $SkipRun) {
    Write-Header "运行 QGroundControl"

    if (-not (Test-Path $ExePath)) {
        Write-ErrorMsg "找不到可执行文件: $ExePath"
        Write-Host "  请先运行编译: .\scripts\build_and_run.ps1 -SkipRun" -ForegroundColor DarkYellow
        exit 1
    }

    Write-OK "可执行文件: $ExePath"

    # 构建运行时的 PATH
    $runtimePaths = @()

    # Qt bin
    $qtBin = Join-Path $QtRoot "bin"
    if (Test-Path $qtBin) {
        $runtimePaths += $qtBin
    }

    # GStreamer bin
    if ($hasGStreamer) {
        $gstBin = Join-Path $GStreamerDir "bin"
        if (Test-Path $gstBin) {
            $runtimePaths += $gstBin
        }
    }

    # 设置环境变量
    $env:PATH = ($runtimePaths + $env:PATH) -join [IO.Path]::PathSeparator

    # Qt 插件路径
    $qtPlugins = Join-Path $QtRoot "plugins"
    if (Test-Path $qtPlugins) {
        $env:QT_PLUGIN_PATH = $qtPlugins
    }

    # Qt QML 路径
    $qtQml = Join-Path $QtRoot "qml"
    if (Test-Path $qtQml) {
        $env:QML2_IMPORT_PATH = $qtQml
    }

    Write-Step "启动 QGroundControl..."
    Write-Host "  按 Ctrl+C 停止程序`n"

    $process = Start-Process -FilePath $ExePath -WorkingDirectory (Split-Path $ExePath) -PassThru
    Write-Host "  PID: $($process.Id)"

    $process.WaitForExit()
    Write-OK "QGroundControl 已退出 (exit code: $($process.ExitCode))"
}

Write-Header "完成"
