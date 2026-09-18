<# 
.SYNOPSIS
  Removes the local Codex RTL copy and desktop shortcuts.
#>
param(
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$InstallRoot = Join-Path $env:LOCALAPPDATA 'OpenAI\CodexRtl'
$StatePath = Join-Path $InstallRoot 'patch-state.json'
$IdentityPackageName = 'CodexRtl.Local'
$IdentityCertificateSubject = 'CN=Codex RTL Local Package'
$DesktopPath = [Environment]::GetFolderPath('Desktop')
$ShortcutPaths = @(
    (Join-Path $DesktopPath 'Codex RTL.lnk'),
    (Join-Path $DesktopPath 'Codex (Original).lnk'),
    (Join-Path $DesktopPath 'ChatGPT.lnk'),
    (Join-Path $DesktopPath 'Launch Codex RTL.lnk'),
    (Join-Path $DesktopPath 'Launch Codex Original.lnk')
)

function Resolve-FullPath([string]$Path) {
    $full = [System.IO.Path]::GetFullPath($Path)
    return $full.TrimEnd('\')
}

function Assert-UnderPath([string]$Child, [string]$Parent) {
    $childFull = Resolve-FullPath $Child
    $parentFull = Resolve-FullPath $Parent
    if (-not ($childFull.Equals($parentFull, [System.StringComparison]::OrdinalIgnoreCase) -or
              $childFull.StartsWith($parentFull + '\', [System.StringComparison]::OrdinalIgnoreCase))) {
        throw "Refusing to delete outside expected directory. Child='$childFull' Parent='$parentFull'"
    }
}

function Read-PatchState {
    if (-not (Test-Path -LiteralPath $StatePath -PathType Leaf)) { return $null }
    try {
        return Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json
    } catch {
        return $null
    }
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Remove-RtlPackageIdentity([object]$State) {
    $packages = @(Get-AppxPackage -Name $IdentityPackageName -ErrorAction SilentlyContinue)
    foreach ($package in $packages) {
        if ($DryRun) {
            Write-Host "DRY RUN remove Codex RTL package identity: $($package.PackageFullName)"
        } else {
            Remove-AppxPackage -Package $package.PackageFullName -ErrorAction Stop
            Write-Host "Removed Codex RTL package identity: $($package.PackageFullName)" -ForegroundColor Green
        }
    }

    if (-not $State -or -not ($State.PSObject.Properties.Name -contains 'rtlIdentityCertificateThumbprint')) {
        return
    }

    $thumbprint = [string]$State.rtlIdentityCertificateThumbprint
    if (-not $thumbprint) { return }

    foreach ($storePath in @('Cert:\LocalMachine\TrustedPeople', 'Cert:\CurrentUser\My')) {
        $certificatePath = Join-Path $storePath $thumbprint
        if (-not (Test-Path -LiteralPath $certificatePath -PathType Leaf)) { continue }
        $certificate = Get-Item -LiteralPath $certificatePath
        if ($certificate.Subject -ne $IdentityCertificateSubject) {
            throw "Refusing to remove unexpected certificate from $storePath."
        }
        if ($DryRun) {
            Write-Host "DRY RUN remove Codex RTL signing certificate from $storePath"
        } else {
            Remove-Item -LiteralPath $certificatePath -Force
            Write-Host "Removed Codex RTL signing certificate from $storePath" -ForegroundColor Green
        }
    }
}

$expectedParent = Join-Path $env:LOCALAPPDATA 'OpenAI'
Assert-UnderPath $InstallRoot $expectedParent
if (-not $DryRun -and -not (Test-IsAdministrator)) {
    throw 'Administrator rights are required to remove the Codex RTL package identity certificate. Open PowerShell as Administrator and rerun this command.'
}
$state = Read-PatchState
Remove-RtlPackageIdentity $state

foreach ($shortcutPath in $ShortcutPaths) {
    if (Test-Path -LiteralPath $shortcutPath) {
        if ($DryRun) {
            Write-Host "DRY RUN remove shortcut: $shortcutPath"
        } else {
            Remove-Item -LiteralPath $shortcutPath -Force
            Write-Host "Removed shortcut: $shortcutPath" -ForegroundColor Green
        }
    }
}

if (Test-Path -LiteralPath $InstallRoot) {
    if ($DryRun) {
        Write-Host "DRY RUN remove folder: $InstallRoot"
    } else {
        Remove-Item -LiteralPath $InstallRoot -Recurse -Force
        Write-Host "Removed local Codex RTL folder: $InstallRoot" -ForegroundColor Green
    }
} else {
    Write-Host "Codex RTL folder was not found: $InstallRoot" -ForegroundColor Yellow
}

if ($DryRun) {
    Write-Host "Dry run completed. No files were changed." -ForegroundColor Green
}
