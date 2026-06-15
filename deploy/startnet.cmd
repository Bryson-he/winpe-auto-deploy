@echo off

:: =====================================================================
:: WinPE Automated Deployment Script
:: https://github.com/YOUR_USERNAME/winpe-auto-deploy
::
:: Launches the HTA progress UI then runs deployment steps sequentially.
:: Communicates with the HTA via flag files on X:\ (WinPE RAM disk).
:: =====================================================================

:: Launch HTA progress UI - detached so it doesn't create a new console window
wscript.exe //B //NoLogo X:\deploy\launch_hta.vbs
ping -n 3 127.0.0.1 >nul 2>&1

:: ── Find USB drive containing install.wim ─────────────────────────────────
set USB=
for %%d in (C D E F G H I J K L M N O P Q R T U V Y Z) do (
    if exist %%d:\sources\install.wim set USB=%%d
)

if not defined USB (
    echo. > X:\s_error_usb
    ping -n 30 127.0.0.1 >nul 2>&1
    exit /b 1
)
echo %USB% > X:\s_usb

:: ── Step 1: Partition ─────────────────────────────────────────────────────
echo. > X:\s_step1
diskpart /s X:\deploy\partition.txt
if %errorlevel% neq 0 (
    echo. > X:\s_error_part
    ping -n 30 127.0.0.1 >nul 2>&1
    exit /b 1
)
echo. > X:\s_step1_done

:: ── Step 2: Apply Image ───────────────────────────────────────────────────
echo. > X:\s_step2
dism /Apply-Image /ImageFile:"%USB%:\sources\install.wim" /Index:1 /ApplyDir:W:\
if %errorlevel% neq 0 (
    echo. > X:\s_error_dism
    ping -n 30 127.0.0.1 >nul 2>&1
    exit /b 1
)
echo. > X:\s_step2_done

:: ── Step 3: Boot Record ───────────────────────────────────────────────────
echo. > X:\s_step3
bcdboot W:\Windows /s S: /f UEFI
if %errorlevel% neq 0 (
    echo. > X:\s_error_bcd
    ping -n 30 127.0.0.1 >nul 2>&1
    exit /b 1
)
echo. > X:\s_step3_done

:: ── Step 4: Done - reboot ─────────────────────────────────────────────────
echo. > X:\s_step4_done
ping -n 16 127.0.0.1 >nul 2>&1
wpeutil reboot
