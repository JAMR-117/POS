@echo off
chcp 65001 >nul
title POS Backend Server Launcher

echo ============================================================
echo         INICIANDO BACKEND SERVIDOR GO (POS OFFLINE)
echo ============================================================

echo [1/3] Verificando y cerrando instancias previas...
taskkill /F /IM pos_backend.exe /T >nul 2>&1

cd /d "C:\POS\backend"
if %errorlevel% neq 0 (
    echo [ERROR] No se encontro el directorio C:\POS\backend
    exit /b 1
)

echo [2/3] Compilando pos_backend.exe...
go build -o pos_backend.exe ./cmd/api
if %errorlevel% neq 0 (
    echo [ERROR] Fallo la compilacion de pos_backend.exe.
    exit /b 1
)
echo [OK] Compilacion exitosa.

echo [3/3] Iniciando pos_backend.exe en segundo plano...
start "POS Backend Server" "C:\POS\backend\pos_backend.exe"

echo ============================================================
echo  [OK] Backend iniciado correctamente en:
echo        * http://127.0.0.1:8080
echo        * Healthcheck: http://127.0.0.1:8080/health
echo        * Sync API:    http://127.0.0.1:8080/api/v1/sync
echo ============================================================
exit /b 0
