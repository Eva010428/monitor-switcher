@echo off
REM Monitor Switcher - Windows Launcher
REM If MONITOR_SERVER_URL is set, queries the hub server for the target VCP code.
REM Falls back to local config/monitors.json if server is unreachable.

cd /d "%~dp0"

if not exist "bin\monitor_switcher.exe" (
    echo Error: monitor_switcher.exe not found in bin directory
    echo Please compile the project first. See windows\BUILD.md for instructions.
    pause
    exit /b 1
)

REM ── Server-aware mode ─────────────────────────────────────────────────────
if defined MONITOR_SERVER_URL (
    echo Querying monitor hub: %MONITOR_SERVER_URL%

    REM Detect local IP
    for /f "delims=" %%I in ('powershell -NoProfile -Command ^
        "[Net.Dns]::GetHostAddresses('') | Where-Object { $_.AddressFamily -eq 'InterNetwork' -and $_ -ne '127.0.0.1' } | Select-Object -First 1 -ExpandProperty IPAddressToString"') do set MY_IP=%%I

    if not defined MY_IP (
        echo Could not detect local IP, falling back to local config.
        goto :local_fallback
    )

    REM Query /api/switch  (-Compress keeps response on one line so the variable is intact)
    for /f "delims=" %%R in ('powershell -NoProfile -Command ^
        "try { (Invoke-RestMethod -Uri '%MONITOR_SERVER_URL%/api/switch?current=%MY_IP%' -Method GET -TimeoutSec 5) | ConvertTo-Json -Depth 5 -Compress } catch { '' }"') do set API_RESPONSE=%%R

    if "%API_RESPONSE%"=="" (
        echo Server unreachable, falling back to local config.
        goto :local_fallback
    )

    REM Parse action
    for /f "delims=" %%A in ('powershell -NoProfile -Command ^
        "('%API_RESPONSE%' | ConvertFrom-Json).action"') do set ACTION=%%A

    if "%ACTION%"=="switch" (
        for /f "delims=" %%N in ('powershell -NoProfile -Command ^
            "('%API_RESPONSE%' | ConvertFrom-Json).target.name"') do set TARGET_NAME=%%N
        echo Switching to: %TARGET_NAME%
        powershell -NoProfile -Command ^
            "$t = ('%API_RESPONSE%' | ConvertFrom-Json).target; $ids = @(& '.\bin\monitor_switcher.exe' detect 2>$null | Select-String 'Display\s+(\d+)' | ForEach-Object { $_.Matches[0].Groups[1].Value }); if ($t.vcp_codes) { $codes = @($t.vcp_codes.PSObject.Properties | Sort-Object {[int]$_.Name} | ForEach-Object { $_.Value }); for ($i=0; $i -lt [Math]::Min($ids.Count, $codes.Count); $i++) { & '.\bin\monitor_switcher.exe' setvcp $ids[$i] 60 $codes[$i] } } else { $vcp = $t.vcp_code; $ids | ForEach-Object { & '.\bin\monitor_switcher.exe' setvcp $_ 60 $vcp } }"
        exit /b 0
    )

    if "%ACTION%"=="choose" (
        echo Multiple targets available. Choose one:
        powershell -NoProfile -Command ^
            "$opts = ('%API_RESPONSE%' | ConvertFrom-Json).options; for ($i=0; $i -lt $opts.Count; $i++) { $vcp = if ($opts[$i].vcp_codes) { ($opts[$i].vcp_codes.PSObject.Properties | ForEach-Object { \"$($_.Name)=$($_.Value)\" }) -join ',' } else { $opts[$i].vcp_code }; Write-Host \"  [$($i+1)] $($opts[$i].name) (VCP $vcp)\" }"
        set /p CHOICE="Enter number: "
        for /f "delims=" %%N in ('powershell -NoProfile -Command ^
            "$opts = ('%API_RESPONSE%' | ConvertFrom-Json).options; $opts[%CHOICE%-1].name"') do set TARGET_NAME=%%N
        echo Switching to: %TARGET_NAME%
        powershell -NoProfile -Command ^
            "$t = ('%API_RESPONSE%' | ConvertFrom-Json).options[%CHOICE%-1]; $ids = @(& '.\bin\monitor_switcher.exe' detect 2>$null | Select-String 'Display\s+(\d+)' | ForEach-Object { $_.Matches[0].Groups[1].Value }); if ($t.vcp_codes) { $codes = @($t.vcp_codes.PSObject.Properties | Sort-Object {[int]$_.Name} | ForEach-Object { $_.Value }); for ($i=0; $i -lt [Math]::Min($ids.Count, $codes.Count); $i++) { & '.\bin\monitor_switcher.exe' setvcp $ids[$i] 60 $codes[$i] } } else { $vcp = $t.vcp_code; $ids | ForEach-Object { & '.\bin\monitor_switcher.exe' setvcp $_ 60 $vcp } }"
        exit /b 0
    )

    echo Unexpected server response, falling back to local config.
    goto :local_fallback
)

REM ── Local config fallback ─────────────────────────────────────────────────
:local_fallback
if "%1"=="" (
    bin\monitor_switcher.exe switch mac
) else (
    bin\monitor_switcher.exe %*
)

if errorlevel 1 (
    if "%1"=="" pause
)
