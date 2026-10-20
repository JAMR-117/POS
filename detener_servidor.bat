@echo off
chcp 65001 >nul
title POS Backend Server Stopper

echo ============================================================
echo         DETENIENDO BACKEND SERVIDOR GO
echo ============================================================

taskkill /F /IM pos_backend.exe /T >nul 2>&1
if %errorlevel% equ 0 (
    echo [OK] El servidor pos_backend.exe fue detenido exitosamente.
) else (
    echo [INFO] No habia ninguna instancia de pos_backend.exe en ejecucion.
)

echo ============================================================
exit /b 0
