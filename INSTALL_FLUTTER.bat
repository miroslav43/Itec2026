@echo off
echo ============================================
echo iTEC OVERRIDE - Flutter Installer
echo ============================================
echo.

echo 1. Descarc Flutter SDK...
if not exist "C:\flutter" (
    echo Creare folder C:\flutter...
    mkdir C:\flutter
)

echo 2. Te rugam descarca manual Flutter SDK de la:
echo https://docs.flutter.dev/get-started/install/windows
echo.
echo 3. Extrage arhiva in C:\flutter
echo 4. Adauga C:\flutter\bin la PATH-ul sistemului
echo 5. Ruleaza 'flutter doctor' pentru a verifica
echo.
echo Cand ai terminat, ruleaza acest script din nou.
echo.
pause
