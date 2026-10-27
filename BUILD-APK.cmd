@echo off
setlocal
pushd "%~dp0"
if not exist "android\app\debug.keystore" (
  echo Missing android\app\debug.keystore. Keep your original signing file.
  goto :failed
)
if not exist "android\local.properties" (
  echo Missing android\local.properties. Keep your original SDK configuration.
  goto :failed
)
where node >nul 2>&1
if errorlevel 1 (
  echo Node.js is not available in PATH.
  goto :failed
)
call node scripts\configure.mjs --check
if errorlevel 1 goto :failed
call npm ci --no-audit --no-fund
if errorlevel 1 goto :failed
call node scripts\embed-html.mjs prototype-v4.55.0.html
if errorlevel 1 goto :failed
call node scripts\verify-release.mjs
if errorlevel 1 goto :failed
set NODE_ENV=production
cd android
call .\gradlew.bat assembleRelease -PreactNativeArchitectures=arm64-v8a
if errorlevel 1 goto :failed
if not exist "app\build\outputs\apk\release\app-release.apk" goto :failed
start "" explorer.exe "%CD%\app\build\outputs\apk\release"
echo APK created successfully: app-release.apk
popd
pause
exit /b 0
:failed
echo Build did not finish. Copy the error above for troubleshooting.
popd
pause
exit /b 1
