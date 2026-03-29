@echo off
echo Building APK with dart defines...
C:\Users\ghile\Downloads\flutter_windows_3.19.6-stable\flutter\bin\flutter.bat build apk --release --dart-define-from-file=.dart_env
copy mobile_app\build\app\outputs\flutter-apk\app-release.apk "C:\Users\ghile\Desktop\app-release.apk"
echo.
echo APK: C:\Users\ghile\Desktop\app-release.apk
