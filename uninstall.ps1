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

$expectedParent = Join-Path $env:LOCALAPPDATA 'OpenAI'
Assert-UnderPath $InstallRoot $expectedParent

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
