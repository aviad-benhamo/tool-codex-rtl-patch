<#
.SYNOPSIS
  Activates the current Codex Desktop window without terminating processes.

.DESCRIPTION
  This taskbar entry point is deliberately separate from launch-codex.ps1.
  It only targets the installed MSIX app folder and the local RTL copy.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$installRoot = Join-Path $env:LOCALAPPDATA 'OpenAI\CodexRtl'
$rtlAppDir = Join-Path $installRoot 'app'
$statePath = Join-Path $installRoot 'patch-state.json'
$originalAppUserModelId = 'OpenAI.Codex_2p2nqsd0c76g0!App'

function Resolve-FullPath([string]$Path) {
    if (-not $Path) { return $null }
    try { return [System.IO.Path]::GetFullPath($Path).TrimEnd('\') } catch { return $null }
}

function Test-UnderPath([string]$Child, [string]$Parent) {
    $childFull = Resolve-FullPath $Child
    $parentFull = Resolve-FullPath $Parent
    if (-not $childFull -or -not $parentFull) { return $false }

    return $childFull.Equals($parentFull, [System.StringComparison]::OrdinalIgnoreCase) -or
        $childFull.StartsWith($parentFull + '\', [System.StringComparison]::OrdinalIgnoreCase)
}

function Resolve-CodexRuntimeExecutable([string]$AppDir) {
    foreach ($executableName in @('ChatGPT.exe', 'Codex.exe')) {
        $candidate = Join-Path $AppDir $executableName
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
    return $null
}

function Get-CodexPackage {
    return Get-AppxPackage -Name 'OpenAI.Codex' -ErrorAction SilentlyContinue |
        Sort-Object Version -Descending |
        Select-Object -First 1
}

function Get-SupportedAppDirs {
    $appDirs = @()
    if (Test-Path -LiteralPath $rtlAppDir -PathType Container) { $appDirs += $rtlAppDir }

    $pkg = Get-CodexPackage
    if ($pkg -and $pkg.InstallLocation) {
        $originalAppDir = Join-Path $pkg.InstallLocation 'app'
        if (Test-Path -LiteralPath $originalAppDir -PathType Container) { $appDirs += $originalAppDir }
    }

    return $appDirs | Select-Object -Unique
}

function Get-SupportedRuntimeProcesses([string[]]$AppDirs) {
    if ($AppDirs.Count -eq 0) { return @() }

    $runtimeExecutableNames = @('ChatGPT.exe', 'Codex.exe')
    return Get-CimInstance Win32_Process |
        Where-Object {
            $processPath = [string]$_.ExecutablePath
            $processPath -and
            ($runtimeExecutableNames -contains $_.Name) -and
            @($AppDirs | Where-Object { Test-UnderPath $processPath $_ }).Count -gt 0
        }
}

function Initialize-WindowActivator {
    if ('CodexTaskbarWindowActivator' -as [type]) { return }

    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class CodexTaskbarWindowActivator {
    private const int SW_RESTORE = 9;
    private const uint GW_OWNER = 4;
    private delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")] private static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);
    [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern bool ShowWindow(IntPtr hWnd, int command);
    [DllImport("user32.dll")] private static extern IntPtr GetWindow(IntPtr hWnd, uint command);
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
    [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern bool BringWindowToTop(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern IntPtr SetFocus(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr hWnd, IntPtr processId);
    [DllImport("kernel32.dll")] private static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")] private static extern bool AttachThreadInput(uint attachId, uint attachToId, bool attach);

    public static IntPtr FindVisibleTopLevelWindow(int[] processIds) {
        var wanted = new HashSet<int>(processIds);
        IntPtr match = IntPtr.Zero;
        EnumWindows((hWnd, ignored) => {
            if (!IsWindowVisible(hWnd) || GetWindow(hWnd, GW_OWNER) != IntPtr.Zero) return true;
            uint processId;
            GetWindowThreadProcessId(hWnd, out processId);
            if (wanted.Contains((int)processId)) { match = hWnd; return false; }
            return true;
        }, IntPtr.Zero);
        return match;
    }

    public static bool Activate(IntPtr hWnd) {
        if (hWnd == IntPtr.Zero) return false;
        if (IsIconic(hWnd)) ShowWindow(hWnd, SW_RESTORE);

        var foreground = GetForegroundWindow();
        var foregroundThread = foreground == IntPtr.Zero ? 0 : GetWindowThreadProcessId(foreground, IntPtr.Zero);
        var currentThread = GetCurrentThreadId();
        var attached = foregroundThread != 0 && foregroundThread != currentThread &&
            AttachThreadInput(currentThread, foregroundThread, true);
        try {
            BringWindowToTop(hWnd);
            SetForegroundWindow(hWnd);
            SetFocus(hWnd);
            return true;
        } finally {
            if (attached) AttachThreadInput(currentThread, foregroundThread, false);
        }
    }
}
'@
}

function Find-SupportedWindow([object[]]$Processes) {
    if ($Processes.Count -eq 0) { return [IntPtr]::Zero }
    Initialize-WindowActivator
    return [CodexTaskbarWindowActivator]::FindVisibleTopLevelWindow([int[]]@($Processes | ForEach-Object { $_.ProcessId }))
}

function Read-LastSelectedVariant {
    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) { return $null }
    try {
        $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
        if ($state.lastSelectedVariant -in @('Rtl', 'Original')) { return [string]$state.lastSelectedVariant }
    } catch { }
    return $null
}

function Read-RtlAppUserModelId {
    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) { return $null }
    try {
        $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
        if ($state.rtlAppUserModelId -match '^[^!]+!App$') {
            return [string]$state.rtlAppUserModelId
        }
    } catch { }
    return $null
}

function Start-LastSelectedVariant {
    $variant = Read-LastSelectedVariant
    if (-not $variant) { $variant = 'Rtl' }

    if ($variant -eq 'Original') {
        Start-Process -FilePath (Join-Path $env:WINDIR 'explorer.exe') -ArgumentList "shell:AppsFolder\$originalAppUserModelId"
        return
    }

    $rtlAppUserModelId = Read-RtlAppUserModelId
    if (-not $rtlAppUserModelId) {
        throw 'The Codex RTL package identity is not installed. Re-run install.ps1, then use Codex RTL.'
    }
    Start-Process -FilePath (Join-Path $env:WINDIR 'explorer.exe') -ArgumentList "shell:AppsFolder\$rtlAppUserModelId"
}

$appDirs = @(Get-SupportedAppDirs)
$processes = @(Get-SupportedRuntimeProcesses $appDirs)
$window = Find-SupportedWindow $processes
if ($window -ne [IntPtr]::Zero) {
    [CodexTaskbarWindowActivator]::Activate($window) | Out-Null
    return
}

Start-LastSelectedVariant

# A newly started Electron runtime can need a short time before the UI process owns a window.
for ($attempt = 0; $attempt -lt 20; $attempt++) {
    Start-Sleep -Milliseconds 250
    $processes = @(Get-SupportedRuntimeProcesses $appDirs)
    $window = Find-SupportedWindow $processes
    if ($window -ne [IntPtr]::Zero) {
        [CodexTaskbarWindowActivator]::Activate($window) | Out-Null
        break
    }
}
