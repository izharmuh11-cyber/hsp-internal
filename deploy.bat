@echo off
title Haispace P2P iOS Deployer
cd /d "%~dp0"
color 0F

echo.
echo ============================================================
echo   HAISPACE NATIVE APP - One-Click Git Build Trigger
echo ============================================================
echo.

:: 1. Periksa apakah Git sudah terinstall
where git >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Git tidak ditemukan! Silakan instal Git di Windows kamu.
    color 4F
    goto end
)

:: 2. Masukkan pesan commit
set /p commit_msg="Masukkan deskripsi update (atau tekan Enter untuk default): "
if "%commit_msg%"=="" (
    set commit_msg="Auto update: build HaispaceBooths & HaispaceCamera"
)

echo.
echo [1/3] Menambahkan berkas modifikasi (git add)...
git add .

echo.
echo [2/3] Membuat commit lokal (git commit)...
git commit -m "%commit_msg%"
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo [INFO] Tidak ada perubahan kode baru untuk di-commit.
)

echo.
echo [3/3] Mengirim ke GitHub (git push)...
git push origin main
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo ============================================================
    echo   PUSH GAGAL! Periksa koneksi internet atau konflik Git.
    echo ============================================================
    color 4F
    goto end
)

:: Berhasil
echo.
echo ============================================================
echo   PUSH SUKSES! GitHub Actions sedang mengompilasi IPA...
echo ============================================================
echo   Silakan pantau progress dan unduh berkas IPA di:
echo   https://github.com/izharmuh11-cyber/hsp-internal/actions
echo ============================================================
color 2F

:end
echo.
pause
