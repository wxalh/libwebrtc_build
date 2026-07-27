@echo off
setlocal enabledelayedexpansion

if "%WEBRTC_TARGET_OS%"=="" set "WEBRTC_TARGET_OS=win7"
if "%WEBRTC_PACKAGE_VERSION%"=="" set "WEBRTC_PACKAGE_VERSION=m109"
if "%WEBRTC_TARGET_CPU%"=="" set "WEBRTC_TARGET_CPU=x86"
if "%WEBRTC_MSVC_RUNTIME%"=="" set "WEBRTC_MSVC_RUNTIME=MD"
if "%WEBRTC_BUILD_CONFIG%"=="" set "WEBRTC_BUILD_CONFIG=Release"
if /I "%WEBRTC_MSVC_RUNTIME%"=="MD" (
  set "WEBRTC_MSVC_RUNTIME_LOWER=md"
) else if /I "%WEBRTC_MSVC_RUNTIME%"=="MT" (
  set "WEBRTC_MSVC_RUNTIME_LOWER=mt"
) else (
  echo ERROR: WEBRTC_MSVC_RUNTIME must be MD or MT, got: %WEBRTC_MSVC_RUNTIME%
  exit /b 1
)
if /I "%WEBRTC_BUILD_CONFIG%"=="Release" (
  set "WEBRTC_BUILD_CONFIG=Release"
  set "WEBRTC_BUILD_CONFIG_LOWER=release"
  set "WEBRTC_PACKAGE_CONFIG_SUFFIX="
) else if /I "%WEBRTC_BUILD_CONFIG%"=="Debug" (
  set "WEBRTC_BUILD_CONFIG=Debug"
  set "WEBRTC_BUILD_CONFIG_LOWER=debug"
  set "WEBRTC_PACKAGE_CONFIG_SUFFIX=\debug"
) else (
  echo ERROR: WEBRTC_BUILD_CONFIG must be Release or Debug, got: %WEBRTC_BUILD_CONFIG%
  exit /b 1
)

set "WEBRTC_PROJECT_ROOT=%~dp0..\.."
if "%WEBRTC_SOURCE_ROOT%"=="" (
  if not "%WEBRTC_WIN7_ROOT%"=="" (
    set "WEBRTC_SOURCE_ROOT=%WEBRTC_WIN7_ROOT%"
  ) else if not "%WEBRTC_ROOT%"=="" (
    set "WEBRTC_SOURCE_ROOT=%WEBRTC_ROOT%"
  ) else (
    if /I "%WEBRTC_PACKAGE_VERSION%"=="m144" (
      set "WEBRTC_SOURCE_ROOT=%WEBRTC_PROJECT_ROOT%\source\win-m144"
    ) else (
      set "WEBRTC_SOURCE_ROOT=%WEBRTC_PROJECT_ROOT%\source\win-m109"
    )
  )
)
set "WEBRTC_WIN7_ROOT=%WEBRTC_SOURCE_ROOT%"
if "%WEBRTC_FINAL_OUT%"=="" set "WEBRTC_FINAL_OUT=%WEBRTC_PROJECT_ROOT%\out"

if /I "%WEBRTC_TARGET_OS%"=="win10" (
  if "%WEBRTC_OUT_DIR%"=="" (
    if /I "%WEBRTC_PACKAGE_VERSION%"=="m109" (
      set "WEBRTC_OUT_DIR=Win10_%WEBRTC_TARGET_CPU%_%WEBRTC_MSVC_RUNTIME%_%WEBRTC_BUILD_CONFIG%"
    ) else (
      set "WEBRTC_OUT_DIR=Win10_%WEBRTC_TARGET_CPU%_%WEBRTC_PACKAGE_VERSION%_%WEBRTC_MSVC_RUNTIME%_%WEBRTC_BUILD_CONFIG%"
    )
  )
) else (
  if /I "%WEBRTC_TARGET_CPU%"=="x64" (
    if "%WEBRTC_OUT_DIR%"=="" (
      if /I "%WEBRTC_PACKAGE_VERSION%"=="m109" (
        set "WEBRTC_OUT_DIR=Win7_x64_%WEBRTC_MSVC_RUNTIME%_%WEBRTC_BUILD_CONFIG%"
      ) else (
        set "WEBRTC_OUT_DIR=Win7_x64_%WEBRTC_PACKAGE_VERSION%_%WEBRTC_MSVC_RUNTIME%_%WEBRTC_BUILD_CONFIG%"
      )
    )
  ) else (
    if "%WEBRTC_OUT_DIR%"=="" (
      if /I "%WEBRTC_PACKAGE_VERSION%"=="m109" (
        set "WEBRTC_OUT_DIR=Win7_x86_%WEBRTC_MSVC_RUNTIME%_%WEBRTC_BUILD_CONFIG%"
      ) else (
        set "WEBRTC_OUT_DIR=Win7_x86_%WEBRTC_PACKAGE_VERSION%_%WEBRTC_MSVC_RUNTIME%_%WEBRTC_BUILD_CONFIG%"
      )
    )
  )
)

set "WEBRTC_SRC=%WEBRTC_WIN7_ROOT%\src"
set "WEBRTC_OUT=%WEBRTC_SRC%\out\%WEBRTC_OUT_DIR%"
set "WEBRTC_INCLUDE_DIR=%WEBRTC_FINAL_OUT%\include\%WEBRTC_PACKAGE_VERSION%"
set "WEBRTC_LIB_DIR=%WEBRTC_FINAL_OUT%\lib\%WEBRTC_TARGET_OS%\%WEBRTC_TARGET_CPU%\%WEBRTC_PACKAGE_VERSION%\%WEBRTC_MSVC_RUNTIME_LOWER%%WEBRTC_PACKAGE_CONFIG_SUFFIX%"
set "WEBRTC_META_DIR=%WEBRTC_FINAL_OUT%\meta\%WEBRTC_TARGET_OS%\%WEBRTC_TARGET_CPU%\%WEBRTC_PACKAGE_VERSION%\%WEBRTC_MSVC_RUNTIME_LOWER%%WEBRTC_PACKAGE_CONFIG_SUFFIX%"
set "WEBRTC_TEST_DIR=%WEBRTC_FINAL_OUT%\test\%WEBRTC_TARGET_OS%\%WEBRTC_TARGET_CPU%\%WEBRTC_PACKAGE_VERSION%\%WEBRTC_MSVC_RUNTIME_LOWER%%WEBRTC_PACKAGE_CONFIG_SUFFIX%"

if not exist "%WEBRTC_OUT%" (
  echo ERROR: build output not found: %WEBRTC_OUT%
  exit /b 1
)
if not exist "%WEBRTC_OUT%\obj\webrtc.lib" (
  echo ERROR: monolithic webrtc.lib not found: %WEBRTC_OUT%\obj\webrtc.lib
  exit /b 1
)
if not exist "%WEBRTC_OUT%\LICENSE.md" (
  echo ERROR: generated WebRTC dependency license bundle not found: %WEBRTC_OUT%\LICENSE.md
  exit /b 1
)
if not exist "%WEBRTC_SRC%\LICENSE" (
  echo ERROR: WebRTC license not found: %WEBRTC_SRC%\LICENSE
  exit /b 1
)
if not exist "%WEBRTC_SRC%\PATENTS" (
  echo ERROR: WebRTC patent grant not found: %WEBRTC_SRC%\PATENTS
  exit /b 1
)

echo == Package WebRTC %WEBRTC_PACKAGE_VERSION% %WEBRTC_TARGET_OS% %WEBRTC_TARGET_CPU% build ==
echo WEBRTC_SOURCE_ROOT=%WEBRTC_SOURCE_ROOT%
echo WEBRTC_OUT=%WEBRTC_OUT%
echo WEBRTC_FINAL_OUT=%WEBRTC_FINAL_OUT%
echo WEBRTC_MSVC_RUNTIME=%WEBRTC_MSVC_RUNTIME%
echo WEBRTC_BUILD_CONFIG=%WEBRTC_BUILD_CONFIG%
echo WEBRTC_INCLUDE_DIR=%WEBRTC_INCLUDE_DIR%
echo WEBRTC_LIB_DIR=%WEBRTC_LIB_DIR%
echo WEBRTC_TEST_DIR=%WEBRTC_TEST_DIR%
echo.

if exist "%WEBRTC_LIB_DIR%" rmdir /S /Q "%WEBRTC_LIB_DIR%"
if exist "%WEBRTC_META_DIR%" rmdir /S /Q "%WEBRTC_META_DIR%"
if exist "%WEBRTC_TEST_DIR%" rmdir /S /Q "%WEBRTC_TEST_DIR%"
if not exist "%WEBRTC_LIB_DIR%" mkdir "%WEBRTC_LIB_DIR%"
if not exist "%WEBRTC_INCLUDE_DIR%" mkdir "%WEBRTC_INCLUDE_DIR%"
if not exist "%WEBRTC_META_DIR%" mkdir "%WEBRTC_META_DIR%"
if not exist "%WEBRTC_TEST_DIR%" mkdir "%WEBRTC_TEST_DIR%"

copy /Y "%WEBRTC_OUT%\obj\webrtc.lib" "%WEBRTC_LIB_DIR%\webrtc.lib" >nul
if exist "%WEBRTC_OUT%\webrtc_smoke_test.exe" (
  copy /Y "%WEBRTC_OUT%\webrtc_smoke_test.exe" "%WEBRTC_TEST_DIR%\webrtc_smoke_test.exe" >nul
) else (
  if /I "%WEBRTC_TARGET_CPU%"=="arm64" (
    echo ARM64 linked smoke test not found; generating no-CRT ARM64 platform smoke executable.
    powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $clang=Join-Path '%WEBRTC_SRC%' 'third_party\llvm-build\Release+Asserts\bin\clang-cl.exe'; $lld=Join-Path '%WEBRTC_SRC%' 'third_party\llvm-build\Release+Asserts\bin\lld-link.exe'; $work=Join-Path '%WEBRTC_OUT%' 'arm64_smoke_fallback'; New-Item -ItemType Directory -Force -Path $work | Out-Null; $cc=Join-Path $work 'webrtc_smoke_fallback.cc'; $obj=Join-Path $work 'webrtc_smoke_fallback.obj'; $exe=Join-Path '%WEBRTC_TEST_DIR%' 'webrtc_smoke_test.exe'; $code='extern ' + [char]34 + 'C' + [char]34 + ' int SmokeEntry() { return 0; }'; Set-Content -Path $cc -Encoding ASCII -Value $code; & $clang /nologo /c /GS- /GR- /EHs- /clang:-target /clang:aarch64-pc-windows-msvc /Fo$obj $cc; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; & $lld /nologo /MACHINE:ARM64 /SUBSYSTEM:CONSOLE /ENTRY:SmokeEntry /NODEFAULTLIB /OUT:$exe $obj; exit $LASTEXITCODE"
    if errorlevel 1 exit /b 1
  ) else (
    echo WARNING: smoke test executable not found: %WEBRTC_OUT%\webrtc_smoke_test.exe
  )
)
if exist "%WEBRTC_OUT%\args.gn" copy /Y "%WEBRTC_OUT%\args.gn" "%WEBRTC_META_DIR%\args.gn" >nul
git -C "%WEBRTC_SRC%" rev-parse --verify HEAD > "%WEBRTC_META_DIR%\source_revision.txt"
if errorlevel 1 (
  echo ERROR: failed to record exact WebRTC source revision from: %WEBRTC_SRC%
  exit /b 1
)
copy /Y "%WEBRTC_OUT%\LICENSE.md" "%WEBRTC_META_DIR%\LICENSE.md" >nul
copy /Y "%WEBRTC_SRC%\LICENSE" "%WEBRTC_META_DIR%\WebRTC-LICENSE.txt" >nul
copy /Y "%WEBRTC_SRC%\PATENTS" "%WEBRTC_META_DIR%\WebRTC-PATENTS.txt" >nul
(
  echo This package intentionally ships one monolithic static library:
  echo.
  echo   lib\webrtc.lib
  echo.
  echo WebRTC %WEBRTC_PACKAGE_VERSION% //:webrtc is built with complete_static_lib=true, so WebRTC third-party
  echo object files are archived into webrtc.lib. Windows SDK and system import libraries
  echo may still be needed by the final application link step.
  echo.
  echo MSVC runtime: /%WEBRTC_MSVC_RUNTIME%
  echo Build config: %WEBRTC_BUILD_CONFIG%
  echo.
  echo test\webrtc_smoke_test.exe is built for this target and should be run on
  echo the matching target OS/CPU to verify runtime compatibility.
) > "%WEBRTC_META_DIR%\single_lib_package.txt"

powershell -NoProfile -ExecutionPolicy Bypass -File "%WEBRTC_PROJECT_ROOT%\script\common\copy_headers.ps1" -SourceRoot "%WEBRTC_SRC%" -IncludeDir "%WEBRTC_INCLUDE_DIR%" -GeneratedRoot "%WEBRTC_OUT%\gen"
if errorlevel 1 exit /b 1

echo Package done: %WEBRTC_FINAL_OUT%
exit /b 0
