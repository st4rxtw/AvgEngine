@echo off
:: Usage: setup.bat [--build-type Debug|Release] [--skip-bass] [--skip-glad]
setlocal EnableDelayedExpansion

set BUILD_TYPE=Release
set SKIP_BASS=0
set SKIP_GLAD=0
set SCRIPT_DIR=%~dp0
if "%SCRIPT_DIR:~-1%"=="\" set SCRIPT_DIR=%SCRIPT_DIR:~0,-1%
set DEPS_DIR=%SCRIPT_DIR%\deps
set BUILD_DIR=%SCRIPT_DIR%\build

:parse_args
if "%~1"=="" goto :args_done
if /I "%~1"=="--build-type" ( set BUILD_TYPE=%~2 & shift & shift & goto :parse_args )
if /I "%~1"=="--skip-bass"  ( set SKIP_BASS=1  & shift & goto :parse_args )
if /I "%~1"=="--skip-glad"  ( set SKIP_GLAD=1  & shift & goto :parse_args )
echo [error] Unknown option: %~1 & exit /b 1
:args_done

set PS=powershell -NoProfile -NonInteractive -Command

echo.
%PS% "Write-Host '==> Checking prerequisites...' -ForegroundColor Green"

where git   >nul 2>&1 || ( echo [error] git not found. Install from https://git-scm.com & exit /b 1 )
where cmake >nul 2>&1 || ( echo [error] cmake not found. Install from https://cmake.org & exit /b 1 )

for /f "tokens=3" %%v in ('cmake --version ^| findstr /i "cmake version"') do (
    for /f "tokens=1,2 delims=." %%a in ("%%v") do (
        if %%a LSS 3 ( echo [error] CMake ^>= 3.20 required & exit /b 1 )
        if %%a EQU 3 if %%b LSS 20 ( echo [error] CMake ^>= 3.20 required ^(found %%v^) & exit /b 1 )
    )
)

set PYTHON=
where python  >nul 2>&1 && set PYTHON=python
where python3 >nul 2>&1 && set PYTHON=python3
if "%PYTHON%"=="" (
    echo [warn] Python not found -- glad.h will need to be generated manually.
)

%PS% "$PSVersionTable.PSVersion.Major" >nul 2>&1 || (
    echo [warn] PowerShell 5+ not found. ZIP extraction may fail.
)

for /f "delims=" %%v in ('git --version')   do echo   %%v
for /f "delims=" %%v in ('cmake --version ^| findstr version') do echo   %%v
if not "%PYTHON%"=="" (
    for /f "delims=" %%v in ('%PYTHON% --version') do echo   %%v
)

echo.
%PS% "Write-Host '==> Setting up vcpkg...' -ForegroundColor Green"
if not exist "%DEPS_DIR%" mkdir "%DEPS_DIR%"

set VCPKG_TOOLCHAIN=

if defined VCPKG_ROOT (
    if exist "%VCPKG_ROOT%\vcpkg.exe" (
        echo   Using VCPKG_ROOT=%VCPKG_ROOT%
        set VCPKG_TOOLCHAIN=%VCPKG_ROOT%\scripts\buildsystems\vcpkg.cmake
        goto :vcpkg_done
    )
)

where vcpkg >nul 2>&1 && (
    for /f "delims=" %%p in ('where vcpkg') do (
        set _VCPKG_EXE=%%p
        for %%d in ("!_VCPKG_EXE!") do set VCPKG_ROOT=%%~dpd
        if "!VCPKG_ROOT:~-1!"=="\" set VCPKG_ROOT=!VCPKG_ROOT:~0,-1!
    )
    echo   Found vcpkg in PATH at !VCPKG_ROOT!
    set VCPKG_TOOLCHAIN=!VCPKG_ROOT!\scripts\buildsystems\vcpkg.cmake
    goto :vcpkg_done
)

echo   vcpkg not found -- cloning into deps\vcpkg...
if not exist "%DEPS_DIR%\vcpkg\.git" (
    git clone https://github.com/microsoft/vcpkg.git "%DEPS_DIR%\vcpkg" --depth=1 -q
)
echo   Bootstrapping vcpkg (this takes a minute)...
call "%DEPS_DIR%\vcpkg\bootstrap-vcpkg.bat" -disableMetrics >nul
set VCPKG_ROOT=%DEPS_DIR%\vcpkg
set VCPKG_TOOLCHAIN=%VCPKG_ROOT%\scripts\buildsystems\vcpkg.cmake
echo   vcpkg bootstrapped at %VCPKG_ROOT%
:vcpkg_done

if not exist "%VCPKG_TOOLCHAIN%" (
    echo [error] vcpkg toolchain not found at %VCPKG_TOOLCHAIN%
    exit /b 1
)
echo   Toolchain: %VCPKG_TOOLCHAIN%

set BASS_SDK_DIR=%DEPS_DIR%\bass
set BASS_DIR_FLAG=-DBASS_DIR=%BASS_SDK_DIR%

if %SKIP_BASS%==1 (
    echo [warn] Skipping BASS download ^(--skip-bass^). Pass -DBASS_DIR^=^<path^> to cmake manually.
    set BASS_DIR_FLAG=
    goto :bass_done
)

if exist "%BASS_SDK_DIR%\Bass\bass.h" (
    echo   BASS SDK already present at %BASS_SDK_DIR%
    goto :bass_done
)

echo.
%PS% "Write-Host '==> Downloading BASS audio SDK from un4seen.com...' -ForegroundColor Green"
set TMP_BASS=%DEPS_DIR%\.tmp_bass
if not exist "%TMP_BASS%"         mkdir "%TMP_BASS%"
if not exist "%BASS_SDK_DIR%\Bass" mkdir "%BASS_SDK_DIR%\Bass"
if not exist "%BASS_SDK_DIR%\x64"  mkdir "%BASS_SDK_DIR%\x64"

set BASS_URL=https://www.un4seen.com/files/bass24.zip
echo   Fetching %BASS_URL%
%PS% "try { Invoke-WebRequest -Uri '%BASS_URL%' -OutFile '%TMP_BASS%\bass.zip' -UseBasicParsing -ErrorAction Stop } catch { exit 1 }" 2>nul
if exist "%TMP_BASS%\bass.zip" (
    %PS% "Expand-Archive -Path '%TMP_BASS%\bass.zip' -DestinationPath '%TMP_BASS%\bass' -Force"
    for /r "%TMP_BASS%\bass" %%f in (bass.h) do copy /y "%%f" "%BASS_SDK_DIR%\Bass\" >nul
    if exist "%TMP_BASS%\bass\x64\bass.lib" copy /y "%TMP_BASS%\bass\x64\bass.lib" "%BASS_SDK_DIR%\x64\" >nul
    if exist "%TMP_BASS%\bass\x64\bass.dll" copy /y "%TMP_BASS%\bass\x64\bass.dll" "%BASS_SDK_DIR%\x64\" >nul
    echo   BASS core installed.
) else (
    echo [warn] Could not download BASS. Place files manually:
    echo [warn]   bass.h    -^> %BASS_SDK_DIR%\Bass\bass.h
    echo [warn]   bass.lib  -^> %BASS_SDK_DIR%\x64\bass.lib
    echo [warn]   bass.dll  -^> %BASS_SDK_DIR%\x64\bass.dll
    set BASS_DIR_FLAG=
)

set BASSFX_URL=https://www.un4seen.com/files/bass24-fx.zip
echo   Fetching %BASSFX_URL%
%PS% "try { Invoke-WebRequest -Uri '%BASSFX_URL%' -OutFile '%TMP_BASS%\bass_fx.zip' -UseBasicParsing -ErrorAction Stop } catch { exit 1 }" 2>nul
if exist "%TMP_BASS%\bass_fx.zip" (
    %PS% "Expand-Archive -Path '%TMP_BASS%\bass_fx.zip' -DestinationPath '%TMP_BASS%\bass_fx' -Force"
    for /r "%TMP_BASS%\bass_fx" %%f in (bass_fx.h) do copy /y "%%f" "%BASS_SDK_DIR%\Bass\" >nul
    if exist "%TMP_BASS%\bass_fx\x64\bass_fx.lib" copy /y "%TMP_BASS%\bass_fx\x64\bass_fx.lib" "%BASS_SDK_DIR%\x64\" >nul
    if exist "%TMP_BASS%\bass_fx\x64\bass_fx.dll" copy /y "%TMP_BASS%\bass_fx\x64\bass_fx.dll" "%BASS_SDK_DIR%\x64\" >nul
    echo   BASS_FX installed.
) else (
    echo [warn] Could not download BASS_FX. Place manually:
    echo [warn]   bass_fx.h   -^> %BASS_SDK_DIR%\Bass\bass_fx.h
    echo [warn]   bass_fx.lib -^> %BASS_SDK_DIR%\x64\bass_fx.lib
    echo [warn]   bass_fx.dll -^> %BASS_SDK_DIR%\x64\bass_fx.dll
)

rmdir /s /q "%TMP_BASS%" 2>nul
:bass_done

set GLAD_H=%SCRIPT_DIR%\AvgEngine\Includes\Glad\glad.h
set KHR_H=%SCRIPT_DIR%\AvgEngine\Includes\KHR\khrplatform.h

if %SKIP_GLAD%==1 (
    echo [warn] Skipping glad generation ^(--skip-glad^).
    goto :glad_done
)
if exist "%GLAD_H%" (
    echo   glad.h already present, skipping.
    goto :glad_done
)

echo.
%PS% "Write-Host '==> Generating glad.h (glad 0.1.x, GL 3.2 compatibility)...' -ForegroundColor Green"

if not "%PYTHON%"=="" (
    echo   Installing glad^<0.2 Python package...
    %PYTHON% -m pip install --quiet --upgrade "glad<0.2"

    set GLAD_OUT=%DEPS_DIR%\.glad_gen
    %PYTHON% -m glad --profile=compatibility --api="gl=3.2" --generator=c --out-path="%DEPS_DIR%\.glad_gen"

    if not exist "%SCRIPT_DIR%\AvgEngine\Includes\Glad" mkdir "%SCRIPT_DIR%\AvgEngine\Includes\Glad"
    if not exist "%SCRIPT_DIR%\AvgEngine\Includes\KHR"  mkdir "%SCRIPT_DIR%\AvgEngine\Includes\KHR"
    copy /y "%DEPS_DIR%\.glad_gen\include\glad\glad.h"       "%GLAD_H%" >nul
    copy /y "%DEPS_DIR%\.glad_gen\include\KHR\khrplatform.h" "%KHR_H%"  >nul
    rmdir /s /q "%DEPS_DIR%\.glad_gen" 2>nul
    echo   glad.h written to AvgEngine\Includes\Glad\
    echo   khrplatform.h written to AvgEngine\Includes\KHR\
) else (
    echo [warn] Python not found -- generate glad.h manually:
    echo [warn]   pip install "glad^<0.2"
    echo [warn]   python -m glad --profile=compatibility --api=gl=3.2 --generator=c --out-path=C:\tmp\glad_gen
    echo [warn]   copy C:\tmp\glad_gen\include\glad\glad.h       AvgEngine\Includes\Glad\glad.h
    echo [warn]   copy C:\tmp\glad_gen\include\KHR\khrplatform.h AvgEngine\Includes\KHR\khrplatform.h
)
:glad_done

echo.
%PS% "Write-Host '==> Cloning imgui and implot...' -ForegroundColor Green"
if not exist "%DEPS_DIR%" mkdir "%DEPS_DIR%"

set IMGUI_DIR=%DEPS_DIR%\ImGui
set IMPLOT_DIR=%DEPS_DIR%\implot

if exist "%IMGUI_DIR%\.git" (
    echo   imgui already cloned, pulling latest...
    git -C "%IMGUI_DIR%" pull --ff-only -q
) else (
    echo   Cloning imgui from github.com/ocornut/imgui...
    git clone https://github.com/ocornut/imgui.git "%IMGUI_DIR%" --depth=1 -q
)

if exist "%IMPLOT_DIR%\.git" (
    echo   implot already cloned, pulling latest...
    git -C "%IMPLOT_DIR%" pull --ff-only -q
) else (
    echo   Cloning implot from github.com/epezent/implot...
    git clone https://github.com/epezent/implot.git "%IMPLOT_DIR%" --depth=1 -q
)

echo   imgui  -^> %IMGUI_DIR%
echo   implot -^> %IMPLOT_DIR%

echo.
%PS% "Write-Host '==> Configuring CMake (%BUILD_TYPE%)...' -ForegroundColor Green"
echo   Note: vcpkg will install packages from vcpkg.json on first run -- can take several minutes.

set CMAKE_EXTRA=
if not "%BASS_DIR_FLAG%"=="" set CMAKE_EXTRA=%BASS_DIR_FLAG%

cmake -B "%BUILD_DIR%" -S "%SCRIPT_DIR%" ^
    -G "Visual Studio 17 2022" -A x64 ^
    -DCMAKE_TOOLCHAIN_FILE="%VCPKG_TOOLCHAIN%" ^
    -DCMAKE_BUILD_TYPE=%BUILD_TYPE% ^
    %CMAKE_EXTRA%

echo.
%PS% "Write-Host '==> Setup complete!' -ForegroundColor Green"
echo.
echo   Build (from IDE):  Open build\AvgEngine.sln in Visual Studio
echo   Build (CLI):       cmake --build "%BUILD_DIR%" --config %BUILD_TYPE%
echo   Rebuild clean:     cmake --build "%BUILD_DIR%" --config %BUILD_TYPE% --clean-first
echo.
if "%BASS_DIR_FLAG%"=="" (
    echo [warn] BASS was not configured. Once you have the SDK, re-run cmake:
    echo [warn]   cmake -B build -DBASS_DIR=%BASS_SDK_DIR%
)

endlocal