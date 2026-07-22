# run-web.ps1 - one command to launch Pixel Pomo in Chrome for web testing.
# Frees port 8787 if a stale flutter dev server is holding it, then runs.
# Usage (from anywhere):  .\run-web.ps1   (or)   powershell -ExecutionPolicy Bypass -File run-web.ps1

$port = 8787
$flutter = 'C:\src\flutter\bin\flutter.bat'

# Free the port: kill ONLY a LISTENING dart/flutter process. Never a browser,
# never an unrelated app (a client connection to the port is left alone too).
$owners = netstat -ano | Select-String ":$port\s" | Select-String 'LISTENING' |
  ForEach-Object { ($_.ToString().Trim() -split '\s+')[-1] } | Sort-Object -Unique
foreach ($procId in $owners) {
  if ($procId -notmatch '^\d+$' -or $procId -eq '0') { continue }
  $proc = Get-Process -Id $procId -ErrorAction SilentlyContinue
  if ($proc -and $proc.ProcessName -match 'dart|flutter') {
    Write-Host "Port $port busy - killing stale $($proc.ProcessName) (PID $procId)" -ForegroundColor Yellow
    Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue
  }
  elseif ($proc) {
    Write-Host "Port $port held by $($proc.ProcessName) (PID $procId), not a flutter process - leaving it. Close it, or change `$port in this script." -ForegroundColor Red
  }
}

Set-Location $PSScriptRoot

# Flutter's SDK at C:\src\flutter is a git repo owned by another Windows account
# here; git blocks cross-owner repos ("dubious ownership"), which breaks flutter's
# engine-version lookup. Trust it for THIS user (idempotent - adds only once).
$sdk = 'C:/src/flutter'
if ((git config --global --get-all safe.directory 2>$null) -notcontains $sdk) {
  git config --global --add safe.directory $sdk 2>$null
  Write-Host "Trusted $sdk for git (one-time fix)." -ForegroundColor DarkGray
}

# ponytail: -d chrome is not used. It makes flutter launch its own throwaway Chrome
# profile seeded from .dart_tool\chrome-device; that cache gets written half-way
# (leveldb LOCK files, no Preferences) and then every launch dies with
# "Failed to launch browser" / CDP "connection refused". Serve instead, open Chrome
# by hand - same hot reload, real profile, real DevTools. Delete the poisoned cache
# so a future -d chrome starts clean.
Remove-Item "$PSScriptRoot\.dart_tool\chrome-device" -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "Serving Pixel Pomo -> http://localhost:$port   (open it in Chrome)" -ForegroundColor Cyan
Write-Host "Keys: r=reload  R=restart  q=quit   |   Phone view in Chrome: F12 then Ctrl+Shift+M" -ForegroundColor DarkGray
Write-Host ""
& $flutter run -d web-server --web-port $port
