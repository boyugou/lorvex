param(
    [switch]$NoPull,
    [switch]$Open,
    [switch]$SilentInstall,
    [ValidateSet('nsis', 'msi')]
    [string]$Bundle = 'nsis'
)

$ErrorActionPreference = 'Stop'

if ($env:OS -ne 'Windows_NT') {
    throw 'This script is Windows-only. Use scripts/update_and_install.sh on macOS or scripts/update_and_install_linux.sh on Linux.'
}

# Audit #2995-WIN-L17: pre-fix the `-Bundle msi` switch was accepted
# by `ValidateSet` but produced no installer because
# `app/src-tauri/tauri.conf.json` carries no `bundle.windows.wix`
# block. Tauri's MSI builder requires a WiX 3.x toolchain and a
# `wix` config object with the upgrade code; without those, the
# Tauri build silently skips the MSI target and the script then
# threw "no installer found" deep inside `Get-ChildItem`. Surface
# the configuration gap up-front with a clear remediation pointer
# so a contributor doesn't burn a full release build before
# discovering it.
if ($Bundle -eq 'msi') {
    $tauriConf = Get-Content (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) '..\app\src-tauri\tauri.conf.json') -Raw
    if ($tauriConf -notmatch '"wix"\s*:') {
        throw @'
MSI bundle requested but tauri.conf.json has no `bundle.windows.wix` config.
Tauri 2's MSI builder requires:
  1. WiX Toolset 3.x installed (https://wixtoolset.org/releases/)
  2. A `bundle.windows.wix` block declaring the upgrade code
     (see https://v2.tauri.app/distribute/windows-installer/)
Either configure WiX and re-run, or pass `-Bundle nsis` (the canonical
release channel — see CLAUDE.md "Building a Windows Installer").
'@
    }
}

function Write-Step {
    param([string]$Message)
    Write-Host "==> $Message"
}

function Assert-Command {
    param([string]$Name)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Missing required command: $Name. Install prerequisites first, then rerun this script."
    }
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = (Resolve-Path (Join-Path $scriptDir '..')).Path

Write-Step "Repo: $repoRoot"
Set-Location $repoRoot

if (-not (Test-Path (Join-Path $repoRoot 'app\package.json')) -or -not (Test-Path (Join-Path $repoRoot 'app\src-tauri'))) {
    throw "Repository layout check failed at $repoRoot. Expected app\\package.json and app\\src-tauri\\."
}

Assert-Command -Name git
Assert-Command -Name node
Assert-Command -Name npm

if (-not $NoPull) {
    Write-Step "Pulling latest main"
    git pull --ff-only origin main
} else {
    Write-Step "Skipping git pull"
}

if (-not (Test-Path "package-lock.json")) {
    throw "Missing package-lock.json; refusing to install mutable npm dependencies. Restore the committed lockfile or run an explicit development bootstrap outside this installer."
}

Write-Step "Installing npm dependencies from package-lock.json"
npm ci

Write-Step "Building Windows bundle ($Bundle)"
# Forward --locked after Tauri's Cargo separator so install smoke builds use
# the committed Cargo.lock instead of silently re-resolving dependencies.
npm run -w app tauri:build -- --bundles $Bundle -- --locked

$bundleDir = Join-Path $repoRoot "app/src-tauri/target/release/bundle/$Bundle"
if (-not (Test-Path $bundleDir)) {
    throw "Build finished but bundle directory not found: $bundleDir"
}

$installer = $null
if ($Bundle -eq 'nsis') {
    $installer = Get-ChildItem -Path $bundleDir -File -Filter '*.exe' |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
} else {
    $installer = Get-ChildItem -Path $bundleDir -File -Filter '*.msi' |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
}

if ($null -eq $installer) {
    throw "Build finished but no installer found in: $bundleDir"
}

Write-Step "Running installer: $($installer.FullName)"
if ($Bundle -eq 'nsis' -and $SilentInstall) {
    Start-Process -FilePath $installer.FullName -ArgumentList '/S' -Wait
} elseif ($Bundle -eq 'msi' -and $SilentInstall) {
    Start-Process -FilePath 'msiexec.exe' -ArgumentList '/i', $installer.FullName, '/quiet', '/norestart' -Wait
} else {
    Start-Process -FilePath $installer.FullName -Wait
}

if ($Open) {
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Programs\Lorvex\Lorvex.exe'),
        (Join-Path $env:ProgramFiles 'Lorvex\Lorvex.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Lorvex\Lorvex.exe')
    ) | Where-Object { $_ -and (Test-Path $_) }

    if ($candidates.Count -gt 0) {
        Write-Step "Opening $($candidates[0])"
        Start-Process -FilePath $candidates[0]
    } else {
        Write-Warning "Install completed, but Lorvex.exe was not found in common paths."
    }
}

Write-Step "Done."
