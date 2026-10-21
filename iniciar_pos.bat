@echo off
chcp 65001 >nul
title POS Cerrajería - Sistema Completo

echo ============================================================
echo      INICIANDO SISTEMA POS CERRAJERÍA OFFLINE-FIRST
echo ============================================================

echo [1/4] Verificando contenedor Docker de PostgreSQL...
docker start pos-postgres >nul 2>&1

echo [2/4] Verificando y arrancando Servidor Backend Go...
taskkill /F /IM pos_backend.exe /T >nul 2>&1
cd /d "C:\POS\backend"
start "POS Backend Server" /min "C:\POS\backend\pos_backend.exe"

echo [3/4] Esperando inicializacion y auto-siembra del Backend...
timeout /t 3 /nobreak >nul

echo [4/4] Levantando Cliente Flutter Web en puerto fijo 3000...
echo (Mantiene base de datos IndexedDB persistente en el navegador)
cd /d "C:\POS\client"
flutter run -d chrome --web-port 3000

pause
