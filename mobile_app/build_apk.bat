@echo off
echo ========================================
echo  Building APK with .dart_env secrets
echo ========================================
C:\flutter\flutter\bin\flutter.bat build apk --release --dart-define-from-file=.dart_env
echo.
if %ERRORLEVEL% == 0 (
  echo BUILD SUCCESSFUL
  echo APK: build\app\outputs\flutter-apk\app-release.apk
) else (
  echo BUILD FAILED
)
pause
