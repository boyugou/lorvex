#requires -Version 5.1
#
# Build a signed Windows NSIS installer for Lorvex.
#
# Audit #3037 WIN1 + WIN-GAP3: the repo had no analog of `build_dmg.sh`
# (macOS) for Windows. The CI
# release workflow set the certificate thumbprint via `tauri.conf.json`
# patching, but no documented local invocation existed — a developer
# producing a release build had to manually edit `tauri.conf.json`,
# remember the env-var → thumbprint substitution, and revert the file.
# This script automates the whole flow:
#
#   1. Source `.env.build` for `WINDOWS_CERTIFICATE_THUMBPRINT`, or import
#      `WINDOWS_CERTIFICATE_FILE` / base64 `WINDOWS_CERTIFICATE` and derive
#      the thumbprint from the imported PFX certificate.
#   2. Patch `tauri.conf.json` in-place with the thumbprint, build,
#      then restore the original on exit (whether the build succeeded
#      or panicked) so the working tree stays clean.
#   3. Remove any certificate/private key material imported by this script.
#   4. Surface the produced installer path so a follow-up signing or
#      upload step can find it deterministically.
#
# Mirrors the structure of `scripts/build_dmg.sh` — keep the two
# scripts' shape aligned so contributors can reason about both
# platforms uniformly.

[CmdletBinding()]
param(
    [ValidateSet('nsis', 'msi')]
    [string]$Bundle = 'nsis'
)

$ErrorActionPreference = 'Stop'

if ($env:OS -ne 'Windows_NT') {
    throw 'This script is Windows-only. Use scripts/build_dmg.sh for the macOS developer/reference build.'
}

$repoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$tauriConfPath = Join-Path $repoRoot 'app/src-tauri/tauri.conf.json'

# ─── Source signing credentials from .env.build ──────────────────────
#
# `.env.build` is gitignored (per CLAUDE.md "Building a Windows Installer
# (Signed)") so secrets never land in the repo. The .env format is
# `export KEY="value"` for parity with the macOS shell-sourced flow;
# parse it line-by-line and lift KEY=VALUE pairs into the PowerShell
# session env.
$envFile = Join-Path $repoRoot '.env.build'
if (Test-Path $envFile) {
    Get-Content $envFile | ForEach-Object {
        $line = $_.Trim()
        if (-not $line -or $line.StartsWith('#')) { return }
        if ($line -match '^(?:export\s+)?([A-Z_][A-Z0-9_]*)\s*=\s*"?(.*?)"?\s*$') {
            $name = $matches[1]
            $value = $matches[2]
            Set-Item -Path "Env:$name" -Value $value
        }
    }
    Write-Host "==> Loaded Windows credentials from .env.build"
}

function Normalize-Thumbprint {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    return ($Value -replace '[^0-9A-Fa-f]', '').ToUpperInvariant()
}

function Assert-ValidWindowsThumbprint {
    param(
        [string]$Thumbprint,
        [string]$Name = 'WINDOWS_CERTIFICATE_THUMBPRINT'
    )

    if ([string]::IsNullOrWhiteSpace($Thumbprint)) {
        return
    }
    if ($Thumbprint -notmatch '^[0-9A-F]{40}$') {
        throw "$Name must be a 40-character SHA-1 thumbprint after normalization."
    }
}

function Import-WindowsSigningCertificate {
    param(
        [string]$PfxPath,
        [string]$Base64Certificate,
        [string]$Password,
        [string]$ExpectedThumbprint
    )

    $hasPfxPath = -not [string]::IsNullOrWhiteSpace($PfxPath)
    $hasBase64Certificate = -not [string]::IsNullOrWhiteSpace($Base64Certificate)
    if (-not $hasPfxPath -and -not $hasBase64Certificate) {
        return $null
    }
    if ($hasPfxPath -and $hasBase64Certificate) {
        throw 'Set only one Windows PFX input: WINDOWS_CERTIFICATE_FILE or WINDOWS_CERTIFICATE.'
    }
    if ([string]::IsNullOrWhiteSpace($Password)) {
        throw 'WINDOWS_CERTIFICATE_PASSWORD is required when importing WINDOWS_CERTIFICATE_FILE or WINDOWS_CERTIFICATE.'
    }

    $pfxTempDir = $null
    $importedThumbprint = $null
    try {
        if ($hasPfxPath) {
            if (-not (Test-Path -LiteralPath $PfxPath)) {
                throw "WINDOWS_CERTIFICATE_FILE does not exist: $PfxPath"
            }
            $pfxPathToImport = (Resolve-Path -LiteralPath $PfxPath).Path
        } else {
            $pfxTempDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
            New-Item -ItemType Directory -Path $pfxTempDir -Force | Out-Null
            $pfxPathToImport = Join-Path $pfxTempDir 'certificate.pfx'
            [System.IO.File]::WriteAllBytes(
                $pfxPathToImport,
                [Convert]::FromBase64String($Base64Certificate)
            )
        }

        $securePassword = ConvertTo-SecureString -String $Password -AsPlainText -Force
        $imported = Import-PfxCertificate `
            -FilePath $pfxPathToImport `
            -CertStoreLocation Cert:\CurrentUser\My `
            -Password $securePassword `
            -ErrorAction Stop

        $importedCert = @($imported) | Select-Object -First 1
        if (-not $importedCert -or [string]::IsNullOrWhiteSpace($importedCert.Thumbprint)) {
            throw 'Windows PFX import did not return a certificate thumbprint.'
        }

        $importedThumbprint = Normalize-Thumbprint $importedCert.Thumbprint
        Assert-ValidWindowsThumbprint -Thumbprint $importedThumbprint -Name 'Imported PFX thumbprint'
        $expected = Normalize-Thumbprint $ExpectedThumbprint
        Assert-ValidWindowsThumbprint -Thumbprint $expected -Name 'WINDOWS_CERTIFICATE_THUMBPRINT'
        if ($expected -and $importedThumbprint -ne $expected) {
            throw "Imported PFX thumbprint $importedThumbprint does not match WINDOWS_CERTIFICATE_THUMBPRINT $expected."
        }

        Write-Host "==> Imported Authenticode certificate into Cert:\CurrentUser\My"
        return $importedCert
    }
    catch {
        if ($importedThumbprint) {
            Remove-ImportedWindowsSigningCertificate -Thumbprint $importedThumbprint
        }
        throw
    }
    finally {
        if ($pfxTempDir) {
            Remove-Item $pfxTempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Remove-ImportedWindowsSigningCertificate {
    param([string]$Thumbprint)

    $normalizedThumbprint = Normalize-Thumbprint $Thumbprint
    if (-not $normalizedThumbprint) {
        return
    }

    $certPath = "Cert:\CurrentUser\My\$normalizedThumbprint"
    $remaining = Get-Item -LiteralPath $certPath -ErrorAction SilentlyContinue
    if (-not $remaining) {
        return
    }

    Write-Host "==> Removing imported Authenticode certificate from Cert:\CurrentUser\My"
    Remove-Item -LiteralPath $certPath -DeleteKey -Force -ErrorAction Stop
    $remaining = Get-Item -LiteralPath $certPath -ErrorAction SilentlyContinue
    if ($remaining) {
        throw "Imported Authenticode certificate remains after cleanup: $normalizedThumbprint"
    }
}

$requestedThumbprint = Normalize-Thumbprint $env:WINDOWS_CERTIFICATE_THUMBPRINT
Assert-ValidWindowsThumbprint -Thumbprint $requestedThumbprint -Name 'WINDOWS_CERTIFICATE_THUMBPRINT'
$importedCertificateThumbprint = $null
$thumbprint = $requestedThumbprint

# ─── Import optional PFX, patch tauri.conf.json, build, restore ──────
#
# The repo committed `tauri.conf.json` has `certificateThumbprint: null`
# so unsigned dev builds (and non-Windows contributors' source trees)
# stay clean. We mutate the JSON only for the duration of the build,
# then restore the original on exit. If this script imports a PFX first,
# the same try/finally removes the imported certificate and private key.
$originalConf = Get-Content $tauriConfPath -Raw

try {
    $importedCert = Import-WindowsSigningCertificate `
        -PfxPath $env:WINDOWS_CERTIFICATE_FILE `
        -Base64Certificate $env:WINDOWS_CERTIFICATE `
        -Password $env:WINDOWS_CERTIFICATE_PASSWORD `
        -ExpectedThumbprint $requestedThumbprint
    if ($importedCert) {
        $thumbprint = Normalize-Thumbprint $importedCert.Thumbprint
        $importedCertificateThumbprint = $thumbprint
    }

    if ([string]::IsNullOrWhiteSpace($thumbprint)) {
        Write-Warning @'
WINDOWS_CERTIFICATE_THUMBPRINT not set and no Windows PFX input was imported — producing an UNSIGNED installer.
Windows SmartScreen will warn (or block) users running an unsigned .exe.

To sign locally, either:
  1. Install your Authenticode certificate into the Windows certificate store and set WINDOWS_CERTIFICATE_THUMBPRINT.
  2. Or set WINDOWS_CERTIFICATE_FILE plus WINDOWS_CERTIFICATE_PASSWORD.
  3. Or set base64 WINDOWS_CERTIFICATE plus WINDOWS_CERTIFICATE_PASSWORD.

See CLAUDE.md "Building a Windows Installer (Signed)" for the full setup.
'@
    }

    if (-not [string]::IsNullOrWhiteSpace($thumbprint)) {
        Write-Host "==> Patching tauri.conf.json with certificate thumbprint"
        # Mutate the JSON structurally instead of via `-replace`. PowerShell's
        # `-replace` operator interprets `$&`, `$1`, `$+`, etc. in the
        # replacement string, so an Authenticode thumbprint that happened to
        # contain (or be coerced into containing) those tokens would corrupt
        # the JSON. Audit #3054 (M9). ConvertFrom-Json/ConvertTo-Json
        # round-trip the file as data, so the thumbprint is treated as a
        # literal string regardless of contents.
        $confObj = $originalConf | ConvertFrom-Json
        if (-not $confObj.bundle.windows) {
            throw "tauri.conf.json missing bundle.windows section — cannot patch certificateThumbprint"
        }
        $confObj.bundle.windows.certificateThumbprint = $thumbprint
        $patched = $confObj | ConvertTo-Json -Depth 32
        Set-Content -Path $tauriConfPath -Value $patched -NoNewline
    }

    Write-Host "==> Installing npm dependencies"
    npm ci

    Write-Host "==> Verifying Cargo lockfiles"
    npm run verify:cargo-lockfile-integrity

    Write-Host "==> Running tauri build (--bundles $Bundle)"
    npm run -w app tauri:build -- --bundles $Bundle -- --locked
    if ($LASTEXITCODE -ne 0) {
        throw "tauri build failed with exit code $LASTEXITCODE"
    }
}
finally {
    # Always restore — even on failure — so a CI runner with a hot
    # workspace doesn't leak the thumbprint into a subsequent dirty
    # state. `Set-Content -NoNewline` preserves the original LF/CRLF
    # mix that the file shipped with.
    try {
        Set-Content -Path $tauriConfPath -Value $originalConf -NoNewline
        Write-Host "==> Restored tauri.conf.json to committed state"
    }
    finally {
        Remove-ImportedWindowsSigningCertificate -Thumbprint $importedCertificateThumbprint
    }
}

# ─── Surface the produced installer path ─────────────────────────────
$installerCandidates = @()
$installerCandidates += Get-ChildItem -Path "$repoRoot/app/src-tauri/target/release/bundle/$Bundle" -Filter '*-setup.exe' -ErrorAction SilentlyContinue
$installerCandidates += Get-ChildItem -Path "$repoRoot/app/src-tauri/target/release/bundle/$Bundle" -Filter '*.msi'       -ErrorAction SilentlyContinue
$installerCandidates += Get-ChildItem -Path "$repoRoot/app/src-tauri/target/release/bundle/$Bundle" -Filter '*.exe'       -ErrorAction SilentlyContinue

if ($installerCandidates.Count -gt 0) {
    $latest = $installerCandidates | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    Write-Host "==> Built installer: $($latest.FullName)"
} else {
    Write-Warning "No installer artifact found under target/release/bundle/$Bundle"
}
