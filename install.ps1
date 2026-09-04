<# 
.SYNOPSIS
  Installs a local RTL-enabled copy of Codex Desktop.

.DESCRIPTION
  This installer does not modify the Microsoft Store/MSIX package under
  WindowsApps. It copies the Codex app folder to LocalAppData, patches the
  copied app.asar, and creates separate guarded desktop shortcuts for the
  patched RTL copy and the original Microsoft Store application.
#>
param(
    [switch]$DryRun,
    [switch]$Launch,
    [switch]$InstallTaskbarShortcutOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$PatchVersion = '0.1.0'
$AsarPackage = '@electron/asar@4.2.0'
$InstallRoot = Join-Path $env:LOCALAPPDATA 'OpenAI\CodexRtl'
$TargetAppDir = Join-Path $InstallRoot 'app'
$StatePath = Join-Path $InstallRoot 'patch-state.json'
$DesktopPath = [Environment]::GetFolderPath('Desktop')
$RtlShortcutPath = Join-Path $DesktopPath 'Codex RTL.lnk'
$OriginalShortcutPath = Join-Path $DesktopPath 'Codex (Original).lnk'
$ChatGptShortcutPath = Join-Path $DesktopPath 'ChatGPT.lnk'
$LegacyShortcutPaths = @(
    (Join-Path $DesktopPath 'Launch Codex RTL.lnk'),
    (Join-Path $DesktopPath 'Launch Codex Original.lnk')
)
$ExplorerPath = Join-Path $env:WINDIR 'explorer.exe'
$PowerShellPath = Join-Path $PSHOME 'powershell.exe'
$OriginalAppUserModelId = 'OpenAI.Codex_2p2nqsd0c76g0!App'
$OriginalShellTarget = "shell:AppsFolder\$OriginalAppUserModelId"
$ScriptPath = $MyInvocation.MyCommand.Path
$ThisDir = if ($ScriptPath) { Split-Path -Parent $ScriptPath } else { (Get-Location).Path }
$PatchJsSource = Join-Path $ThisDir 'src\codex-rtl-patch.js'
$AsarIntegrityUpdaterSource = Join-Path $ThisDir 'src\update-asar-integrity.ps1'
$LauncherScriptSource = Join-Path $ThisDir 'src\launch-codex.ps1'
$LauncherScriptPath = Join-Path $InstallRoot 'launch-codex.ps1'
$TaskbarActivatorSource = Join-Path $ThisDir 'src\activate-chatgpt.ps1'
$TaskbarActivatorPath = Join-Path $InstallRoot 'activate-chatgpt.ps1'
$TaskbarAppUserModelId = 'com.openai.codex'

function Write-Step([string]$Message) {
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Write-Ok([string]$Message) {
    Write-Host "OK  $Message" -ForegroundColor Green
}

function Write-Warn([string]$Message) {
    Write-Host "WARN $Message" -ForegroundColor Yellow
}

function Resolve-FullPath([string]$Path) {
    $full = [System.IO.Path]::GetFullPath($Path)
    return $full.TrimEnd('\')
}

function Assert-UnderPath([string]$Child, [string]$Parent) {
    $childFull = Resolve-FullPath $Child
    $parentFull = Resolve-FullPath $Parent
    if (-not ($childFull.Equals($parentFull, [System.StringComparison]::OrdinalIgnoreCase) -or
              $childFull.StartsWith($parentFull + '\', [System.StringComparison]::OrdinalIgnoreCase))) {
        throw "Refusing to operate outside expected directory. Child='$childFull' Parent='$parentFull'"
    }
}

function Get-CodexPackage {
    $pkg = Get-AppxPackage -Name 'OpenAI.Codex' -ErrorAction SilentlyContinue |
        Sort-Object Version -Descending |
        Select-Object -First 1
    if ($pkg -and $pkg.InstallLocation) {
        return $pkg
    }
    throw 'OpenAI.Codex package was not found. Install Codex Desktop first.'
}

function Resolve-CodexRuntimeExecutable([string]$AppDir) {
    foreach ($executableName in @('ChatGPT.exe', 'Codex.exe')) {
        $candidate = Join-Path $AppDir $executableName
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }
    }

    throw "No supported Codex Desktop runtime executable was found in: $AppDir. Expected ChatGPT.exe or Codex.exe."
}

function Resolve-CodexRuntimeIconRelativePath([string]$AppDir) {
    foreach ($relativePath in @('resources\icon-chatgpt.ico', 'resources\icon.ico')) {
        if (Test-Path -LiteralPath (Join-Path $AppDir $relativePath) -PathType Leaf) {
            return $relativePath
        }
    }

    return $null
}

function Get-NpxCommand {
    $cmd = Get-Command 'npx.cmd' -ErrorAction SilentlyContinue
    if (-not $cmd) { $cmd = Get-Command 'npx' -ErrorAction SilentlyContinue }
    if (-not $cmd) {
        throw 'Node.js/npm npx was not found. Install Node.js 22+ or newer, then rerun this installer.'
    }
    return $cmd.Source
}

function Assert-LocalPatchFile {
    if (-not (Test-Path -LiteralPath $PatchJsSource -PathType Leaf)) {
        throw "Required local patch file was not found: $PatchJsSource. Restore src\codex-rtl-patch.js in this repository and rerun the installer. Remote downloads are disabled."
    }
}

function Assert-LocalAsarIntegrityUpdater {
    if (-not (Test-Path -LiteralPath $AsarIntegrityUpdaterSource -PathType Leaf)) {
        throw "Required ASAR integrity updater was not found: $AsarIntegrityUpdaterSource"
    }
}

function Assert-LocalLauncherScript {
    if (-not (Test-Path -LiteralPath $LauncherScriptSource -PathType Leaf)) {
        throw "Required launcher script was not found: $LauncherScriptSource"
    }
}

function Assert-LocalTaskbarActivator {
    if (-not (Test-Path -LiteralPath $TaskbarActivatorSource -PathType Leaf)) {
        throw "Required taskbar activator script was not found: $TaskbarActivatorSource"
    }
}

function Install-LauncherScript {
    Assert-LocalLauncherScript

    if ($DryRun) {
        Write-Host "DRY RUN copy launcher script to `"$LauncherScriptPath`""
        return
    }

    New-Item -ItemType Directory -Force $InstallRoot | Out-Null
    Copy-Item -LiteralPath $LauncherScriptSource -Destination $LauncherScriptPath -Force
    Write-Ok "Installed launcher script: $LauncherScriptPath"
}

function Install-TaskbarActivator {
    Assert-LocalTaskbarActivator
    if ($DryRun) {
        Write-Host "DRY RUN copy taskbar activator script to `"$TaskbarActivatorPath`""
        return
    }

    New-Item -ItemType Directory -Force $InstallRoot | Out-Null
    Copy-Item -LiteralPath $TaskbarActivatorSource -Destination $TaskbarActivatorPath -Force
    Write-Ok "Installed taskbar activator script: $TaskbarActivatorPath"
}

function Invoke-RobocopyMirror([string]$Source, [string]$Destination) {
    if ($DryRun) {
        Write-Host "DRY RUN robocopy `"$Source`" `"$Destination`" /MIR"
        return
    }

    New-Item -ItemType Directory -Force $Destination | Out-Null
    & robocopy $Source $Destination /MIR /R:2 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Host
    $code = $LASTEXITCODE
    if ($code -gt 7) {
        throw "robocopy failed with exit code $code"
    }
}

function Remove-TreeBestEffort([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return }
    Assert-UnderPath $Path ([System.IO.Path]::GetTempPath())

    $fullPath = Resolve-FullPath $Path
    $longPath = '\\?\' + $fullPath

    try {
        Remove-Item -LiteralPath $longPath -Recurse -Force -ErrorAction Stop
        return
    } catch {
        Write-Warn "Long-path cleanup failed, retrying normal PowerShell cleanup: $($_.Exception.Message)"
    }

    try {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
        return
    } catch {
        Write-Warn "PowerShell cleanup failed, retrying with .NET: $($_.Exception.Message)"
    }

    try {
        [System.IO.Directory]::Delete($Path, $true)
        return
    } catch {
        Write-Warn "Could not fully remove temporary folder: $Path"
    }
}

function Copy-PatchFile([string]$ExtractDir) {
    $dest = Join-Path $ExtractDir 'webview\assets\codex-rtl-patch.js'
    Assert-LocalPatchFile

    if ($DryRun) {
        Write-Host "DRY RUN copy patch JS to $dest"
        return
    }

    Copy-Item -LiteralPath $PatchJsSource -Destination $dest -Force
}

function Patch-IndexHtml([string]$ExtractDir) {
    $indexPath = Join-Path $ExtractDir 'webview\index.html'
    if ($DryRun) {
        Write-Host "DRY RUN patch $indexPath"
        return
    }

    if (-not (Test-Path -LiteralPath $indexPath)) {
        throw "Codex webview index was not found: $indexPath"
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding -ArgumentList $false
    $html = [System.IO.File]::ReadAllText($indexPath)
    $script = '    <script type="module" crossorigin src="./assets/codex-rtl-patch.js"></script>'

    if ($html -match 'codex-rtl-patch\.js') {
        Write-Ok 'webview/index.html already references codex-rtl-patch.js'
        return
    }

    $mainScriptPattern = '    <script type="module" crossorigin src="./assets/index-[^"]+\.js"></script>'
    if ($html -match $mainScriptPattern) {
        $regex = New-Object System.Text.RegularExpressions.Regex -ArgumentList $mainScriptPattern
        $html = $regex.Replace($html, $script + "`r`n" + '$0', 1)
    } elseif ($html -match '</head>') {
        $html = $html -replace '</head>', ($script + "`r`n</head>")
    } else {
        throw 'Could not find a safe insertion point in webview/index.html'
    }

    [System.IO.File]::WriteAllText($indexPath, $html, $utf8NoBom)
    Write-Ok 'Patched webview/index.html'
}

function Get-AsarUnpackedEntries([string]$AsarPath, [string]$Npx) {
    $listOutput = @(& $Npx --yes $AsarPackage list --is-pack $AsarPath)
    if ($LASTEXITCODE -ne 0) {
        throw "Could not inspect ASAR unpack metadata: $AsarPath"
    }

    return @(
        $listOutput |
            ForEach-Object {
                if ($_ -match '^unpack\s*:\s*\\(.+)$') {
                    $matches[1]
                }
            } |
            Where-Object { $_ } |
            Sort-Object -Unique
    )
}

function ConvertTo-AsarGlob([string[]]$Paths) {
    $normalized = @(
        $Paths |
            Where-Object { $_ } |
            ForEach-Object { $_.Replace('\', '/').TrimStart('/') } |
            Sort-Object -Unique
    )

    if ($normalized.Count -eq 0) {
        return $null
    }
    if ($normalized.Count -eq 1) {
        return $normalized[0]
    }

    return '{' + ($normalized -join ',') + '}'
}

function ConvertTo-AsarFileGlob([string[]]$Paths) {
    return ConvertTo-AsarGlob @(
        $Paths |
            ForEach-Object { Split-Path -Leaf $_ }
    )
}

function Get-AsarUnpackPatterns([string[]]$UnpackedEntries, [string]$ExtractDir) {
    $unpackedDirs = @()
    $unpackedFiles = @()

    foreach ($entry in $UnpackedEntries) {
        $relativePath = $entry.Replace('\', [System.IO.Path]::DirectorySeparatorChar)
        $extractedPath = Join-Path $ExtractDir $relativePath
        if (Test-Path -LiteralPath $extractedPath -PathType Container) {
            $unpackedDirs += $entry
        } elseif (Test-Path -LiteralPath $extractedPath -PathType Leaf) {
            $unpackedFiles += $entry
        } else {
            throw "An unpacked ASAR entry was not extracted: $entry"
        }
    }

    $rootDirs = @(
        $unpackedDirs |
            Where-Object {
                $candidate = $_
                -not ($unpackedDirs | Where-Object {
                    $_ -ne $candidate -and
                    $candidate.StartsWith($_.TrimEnd('\') + '\', [System.StringComparison]::OrdinalIgnoreCase)
                })
            }
    )

    $standaloneFiles = @(
        $unpackedFiles |
            Where-Object {
                $candidate = $_
                -not ($rootDirs | Where-Object {
                    $candidate.StartsWith($_.TrimEnd('\') + '\', [System.StringComparison]::OrdinalIgnoreCase)
                })
            }
    )

    return [PSCustomObject]@{
        # @electron/asar matches --unpack against the basename on Windows.
        # The exact post-pack comparison below rejects any accidental extra match.
        unpack = ConvertTo-AsarFileGlob $standaloneFiles
        unpackDir = ConvertTo-AsarGlob $rootDirs
    }
}

function Assert-AsarUnpackedEntriesPreserved(
    [string[]]$Expected,
    [string[]]$Actual
) {
    $difference = @(Compare-Object -ReferenceObject @($Expected) -DifferenceObject @($Actual))
    if ($difference.Count -gt 0) {
        $summary = ($difference | ForEach-Object { "$($_.SideIndicator) $($_.InputObject)" }) -join '; '
        throw "ASAR unpack metadata changed while applying the RTL patch: $summary"
    }
}

function Patch-Asar([string]$AppDir, [string]$Npx) {
    $asarPath = Join-Path $AppDir 'resources\app.asar'
    if ((-not $DryRun) -and (-not (Test-Path -LiteralPath $asarPath))) {
        throw "app.asar was not found in target app: $asarPath"
    }

    $originalUnpackedEntries = @()
    if (-not $DryRun) {
        $originalUnpackedEntries = @(Get-AsarUnpackedEntries $asarPath $Npx)
    }

    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('codex-rtl-asar-' + [guid]::NewGuid().ToString('N'))
    Assert-UnderPath $tempRoot ([System.IO.Path]::GetTempPath())

    try {
        if (-not $DryRun) {
            New-Item -ItemType Directory -Force $tempRoot | Out-Null
        }

        Write-Step 'Extracting copied app.asar'
        if ($DryRun) {
            Write-Host "DRY RUN $Npx --yes $AsarPackage extract `"$asarPath`" `"$tempRoot`""
        } else {
            & $Npx --yes $AsarPackage extract $asarPath $tempRoot
            if ($LASTEXITCODE -ne 0) { throw 'asar extract failed' }
        }

        Write-Step 'Injecting RTL assets'
        Copy-PatchFile $tempRoot
        Patch-IndexHtml $tempRoot

        Write-Step 'Packing patched app.asar'
        if ($DryRun) {
            Write-Host "DRY RUN $Npx --yes $AsarPackage pack [preserving official unpack metadata] `"$tempRoot`" `"$asarPath`""
        } else {
            $unpackPatterns = Get-AsarUnpackPatterns $originalUnpackedEntries $tempRoot
            $packArguments = @('--yes', $AsarPackage, 'pack')
            if ($unpackPatterns.unpack) {
                $packArguments += @('--unpack', $unpackPatterns.unpack)
            }
            if ($unpackPatterns.unpackDir) {
                $packArguments += @('--unpack-dir', $unpackPatterns.unpackDir)
            }
            $packArguments += @($tempRoot, $asarPath)

            & $Npx @packArguments
            if ($LASTEXITCODE -ne 0) { throw 'asar pack failed' }

            $patchedUnpackedEntries = @(Get-AsarUnpackedEntries $asarPath $Npx)
            Assert-AsarUnpackedEntriesPreserved $originalUnpackedEntries $patchedUnpackedEntries
            Write-Ok "Preserved $($patchedUnpackedEntries.Count) unpacked ASAR entries"
        }
    } finally {
        if ((-not $DryRun) -and (Test-Path -LiteralPath $tempRoot)) {
            Remove-TreeBestEffort $tempRoot
        }
    }
}

function New-WindowsShortcut {
    param(
        [Parameter(Mandatory = $true)][string]$ShortcutPath,
        [Parameter(Mandatory = $true)][string]$TargetPath,
        [string]$Arguments = '',
        [string]$WorkingDirectory = '',
        [string]$IconLocation = '',
        [Parameter(Mandatory = $true)][string]$Description
    )

    if ($DryRun) {
        $argumentSummary = if ($Arguments) { " $Arguments" } else { '' }
        Write-Host "DRY RUN create shortcut `"$ShortcutPath`" -> `"$TargetPath`"$argumentSummary"
        return
    }

    if (-not (Test-Path -LiteralPath $TargetPath -PathType Leaf)) {
        throw "Shortcut target was not found: $TargetPath"
    }

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($ShortcutPath)
    $shortcut.TargetPath = $TargetPath
    if ($Arguments) {
        $shortcut.Arguments = $Arguments
    }
    if ($WorkingDirectory) {
        $shortcut.WorkingDirectory = $WorkingDirectory
    }
    if ($IconLocation -and (Test-Path -LiteralPath $IconLocation -PathType Leaf)) {
        $shortcut.IconLocation = $IconLocation
    }
    $shortcut.Description = $Description
    $shortcut.Save()
    [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($shortcut)
    [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell)
    Write-Ok "Created shortcut: $ShortcutPath"
}

function Set-ShortcutAppUserModelProperties(
    [string]$ShortcutPath,
    [string]$AppUserModelId,
    [string]$RelaunchCommand,
    [string]$RelaunchDisplayName,
    [string]$RelaunchIconResource
) {
    if ($DryRun) {
        Write-Host "DRY RUN set AppUserModel properties on `"$ShortcutPath`""
        return
    }

    if (-not ('CodexTaskbarShortcutProperties' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

[StructLayout(LayoutKind.Sequential, Pack = 4)]
public struct PROPERTYKEY { public Guid fmtid; public uint pid; public PROPERTYKEY(string f, uint p) { fmtid = new Guid(f); pid = p; } }
[StructLayout(LayoutKind.Explicit)]
public struct PROPVARIANT {
    [FieldOffset(0)] public ushort vt;
    [FieldOffset(8)] public IntPtr pointerValue;
    public static PROPVARIANT FromString(string value) { return new PROPVARIANT { vt = 31, pointerValue = Marshal.StringToCoTaskMemUni(value) }; }
}
[ComImport, Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IPropertyStore {
    int GetCount(out uint count); int GetAt(uint index, out PROPERTYKEY key); int GetValue(ref PROPERTYKEY key, out PROPVARIANT value);
    int SetValue(ref PROPERTYKEY key, ref PROPVARIANT value); int Commit();
}
[ComImport, Guid("0000010b-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IPersistFile {
    void GetClassID(out Guid classId); void IsDirty(); void Load([MarshalAs(UnmanagedType.LPWStr)] string path, uint mode);
    void Save([MarshalAs(UnmanagedType.LPWStr)] string path, [MarshalAs(UnmanagedType.Bool)] bool remember); void SaveCompleted([MarshalAs(UnmanagedType.LPWStr)] string path); void GetCurFile([MarshalAs(UnmanagedType.LPWStr)] out string path);
}
[ComImport, Guid("00021401-0000-0000-C000-000000000046")]
public class ShellLink { }
public static class CodexTaskbarShortcutProperties {
    [DllImport("ole32.dll")] private static extern int PropVariantClear(ref PROPVARIANT value);
    private static void Set(IPropertyStore store, uint id, string value) {
        var key = new PROPERTYKEY("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3", id);
        var propertyValue = PROPVARIANT.FromString(value);
        try { Marshal.ThrowExceptionForHR(store.SetValue(ref key, ref propertyValue)); } finally { PropVariantClear(ref propertyValue); }
    }
    public static void SetTaskbarProperties(string path, string appId, string command, string name, string icon) {
        var link = (IPersistFile)new ShellLink();
        link.Load(path, 2);
        var store = (IPropertyStore)link;
        try { Set(store, 5, appId); Set(store, 2, command); Set(store, 4, name); Set(store, 3, icon); Marshal.ThrowExceptionForHR(store.Commit()); link.Save(path, true); }
        finally { Marshal.ReleaseComObject(store); Marshal.ReleaseComObject(link); }
    }
}
'@
    }

    [CodexTaskbarShortcutProperties]::SetTaskbarProperties($ShortcutPath, $AppUserModelId, $RelaunchCommand, $RelaunchDisplayName, $RelaunchIconResource)
}

function New-ChatGptShortcut(
    [string]$RtlAppDir,
    [string]$OriginalAppDir,
    [string]$RuntimeExecutableName,
    [string]$IconRelativePath
) {
    $rtlRuntime = Join-Path $RtlAppDir $RuntimeExecutableName
    if (-not $DryRun -and -not (Test-Path -LiteralPath $rtlRuntime -PathType Leaf)) {
        throw "Resolved Codex RTL runtime was not found: $rtlRuntime"
    }

    $rtlIcon = if ($IconRelativePath) { Join-Path $RtlAppDir $IconRelativePath } else { $null }
    $taskbarIcon = if ($rtlIcon) { $rtlIcon } else { $rtlRuntime }

    Set-ChatGptShortcutTarget $ChatGptShortcutPath $taskbarIcon
    Update-PinnedTaskbarChatGptShortcuts $rtlRuntime $taskbarIcon
}

function Set-ChatGptShortcutTarget([string]$ShortcutPath, [string]$TaskbarIcon) {
    $taskbarArguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$TaskbarActivatorPath`""
    $taskbarRelaunchCommand = "`"$PowerShellPath`" $taskbarArguments"
    New-WindowsShortcut `
        -ShortcutPath $ShortcutPath `
        -TargetPath $PowerShellPath `
        -Arguments $taskbarArguments `
        -WorkingDirectory $InstallRoot `
        -IconLocation $taskbarIcon `
        -Description 'Activate the current Codex or ChatGPT Desktop window without restarting it'
    Set-ShortcutAppUserModelProperties `
        -ShortcutPath $ShortcutPath `
        -AppUserModelId $TaskbarAppUserModelId `
        -RelaunchCommand $taskbarRelaunchCommand `
        -RelaunchDisplayName 'ChatGPT' `
        -RelaunchIconResource "$taskbarIcon,0"
}

function Update-PinnedTaskbarChatGptShortcuts([string]$RtlRuntime, [string]$TaskbarIcon) {
    $pinnedTaskbarPath = Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar'
    if (-not (Test-Path -LiteralPath $pinnedTaskbarPath -PathType Container)) { return }

    $shell = New-Object -ComObject WScript.Shell
    try {
        foreach ($item in Get-ChildItem -LiteralPath $pinnedTaskbarPath -Filter '*.lnk' -File) {
            $shortcut = $shell.CreateShortcut($item.FullName)
            try {
                if (-not $shortcut.TargetPath) {
                    continue
                }
                $targetPath = Resolve-FullPath $shortcut.TargetPath
                if (-not $targetPath -or -not $targetPath.Equals((Resolve-FullPath $RtlRuntime), [System.StringComparison]::OrdinalIgnoreCase)) {
                    continue
                }

                Set-ChatGptShortcutTarget $item.FullName $TaskbarIcon
                Write-Ok "Updated legacy pinned ChatGPT shortcut: $($item.Name)"
            } finally {
                [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($shortcut)
            }
        }
    } finally {
        [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell)
    }
}

function New-CodexShortcuts(
    [string]$RtlAppDir,
    [string]$OriginalAppDir,
    [string]$RuntimeExecutableName,
    [string]$IconRelativePath
) {
    $rtlIcon = if ($IconRelativePath) { Join-Path $RtlAppDir $IconRelativePath } else { $null }
    $originalIcon = if ($IconRelativePath) { Join-Path $OriginalAppDir $IconRelativePath } else { $null }
    $launcherBaseArguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$LauncherScriptPath`""

    New-WindowsShortcut `
        -ShortcutPath $RtlShortcutPath `
        -TargetPath $PowerShellPath `
        -Arguments "$launcherBaseArguments -Variant Rtl" `
        -WorkingDirectory $InstallRoot `
        -IconLocation $rtlIcon `
        -Description 'Open Codex Desktop with local RTL patch and version guard'

    New-WindowsShortcut `
        -ShortcutPath $OriginalShortcutPath `
        -TargetPath $PowerShellPath `
        -Arguments "$launcherBaseArguments -Variant Original" `
        -WorkingDirectory $InstallRoot `
        -IconLocation $originalIcon `
        -Description 'Open original Codex through the Desktop-safe launcher'

    New-ChatGptShortcut $RtlAppDir $OriginalAppDir $RuntimeExecutableName $IconRelativePath
}

function Remove-LegacyShortcuts {
    foreach ($shortcutPath in $LegacyShortcutPaths) {
        if (-not (Test-Path -LiteralPath $shortcutPath)) { continue }
        if ($DryRun) {
            Write-Host "DRY RUN remove legacy shortcut: $shortcutPath"
        } else {
            Remove-Item -LiteralPath $shortcutPath -Force
            Write-Ok "Removed legacy shortcut: $shortcutPath"
        }
    }
}

function Save-State(
    [object]$Package,
    [string]$SourceAppDir,
    [object]$AsarIntegrityResult
) {
    if ($DryRun) { return }
    New-Item -ItemType Directory -Force $InstallRoot | Out-Null
    $lastSelectedVariant = 'Rtl'
    if (Test-Path -LiteralPath $StatePath -PathType Leaf) {
        try {
            $previousState = Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json
            if ($previousState.lastSelectedVariant -in @('Rtl', 'Original')) {
                $lastSelectedVariant = [string]$previousState.lastSelectedVariant
            }
        } catch { }
    }
    $state = [ordered]@{
        patchVersion = $PatchVersion
        installedAt = (Get-Date).ToString('o')
        packageName = $Package.Name
        packageVersion = [string]$Package.Version
        packageInstallLocation = $Package.InstallLocation
        sourceAppDir = $SourceAppDir
        targetAppDir = $TargetAppDir
        installerScriptPath = $ScriptPath
        repositoryDir = $ThisDir
        lastSelectedVariant = $lastSelectedVariant
        asarIntegrityAction = [string]$AsarIntegrityResult.action
        sourceAsarHeaderSha256 = [string]$AsarIntegrityResult.sourceAsarHeaderSha256
        patchedAsarHeaderSha256 = [string]$AsarIntegrityResult.patchedAsarHeaderSha256
        patchedAsarSha256 = (Get-FileHash -LiteralPath (Join-Path $TargetAppDir 'resources\app.asar') -Algorithm SHA256).Hash
    }
    $json = $state | ConvertTo-Json -Depth 5
    $utf8NoBom = New-Object System.Text.UTF8Encoding -ArgumentList $false
    [System.IO.File]::WriteAllText($StatePath, $json + "`n", $utf8NoBom)
}

Write-Step 'Checking local patch file'
Assert-LocalPatchFile
Write-Ok "Using local patch: $PatchJsSource"
Assert-LocalAsarIntegrityUpdater
Write-Ok "Using ASAR integrity updater: $AsarIntegrityUpdaterSource"
Assert-LocalLauncherScript
Write-Ok "Using local launcher script: $LauncherScriptSource"
Assert-LocalTaskbarActivator
Write-Ok "Using local taskbar activator: $TaskbarActivatorSource"

Write-Step 'Finding installed Codex'
$pkg = Get-CodexPackage
$sourceAppDir = Join-Path $pkg.InstallLocation 'app'
$sourceAsar = Join-Path $sourceAppDir 'resources\app.asar'
if (-not (Test-Path -LiteralPath $sourceAsar)) {
    throw "Installed Codex app.asar was not found: $sourceAsar"
}
$sourceRuntime = Resolve-CodexRuntimeExecutable $sourceAppDir
$runtimeExecutableName = Split-Path -Leaf $sourceRuntime
$runtimeIconRelativePath = Resolve-CodexRuntimeIconRelativePath $sourceAppDir
Write-Ok "Found Codex $($pkg.Version)"
Write-Host "Source: $sourceAppDir"
Write-Host "Runtime: $runtimeExecutableName"

Assert-UnderPath $TargetAppDir $InstallRoot
if ($InstallTaskbarShortcutOnly) {
    Write-Step 'Installing ChatGPT taskbar shortcut only'
    Install-TaskbarActivator
    New-ChatGptShortcut $TargetAppDir $sourceAppDir $runtimeExecutableName $runtimeIconRelativePath
    if ($DryRun) {
        Write-Ok 'Taskbar shortcut dry run completed. No files were changed.'
    } else {
        Write-Ok 'ChatGPT taskbar shortcut is installed.'
    }
    return
}

Write-Step 'Checking tools'
$npx = Get-NpxCommand
Write-Ok "Using npx: $npx"

Write-Step 'Copying Codex to a local patchable folder'
Write-Host "Target: $TargetAppDir"
Invoke-RobocopyMirror $sourceAppDir $TargetAppDir

Patch-Asar $TargetAppDir $npx
$targetRuntime = Resolve-CodexRuntimeExecutable $TargetAppDir
Write-Step 'Updating embedded ASAR integrity metadata'
if ($DryRun) {
    Write-Host "DRY RUN update embedded ASAR integrity metadata in `"$targetRuntime`""
    $asarIntegrityResult = [PSCustomObject]@{
        action = 'WouldInspect'
        sourceAsarHeaderSha256 = ''
        patchedAsarHeaderSha256 = ''
    }
} else {
    $asarIntegrityResult = & $AsarIntegrityUpdaterSource `
        -SourceAsarPath $sourceAsar `
        -PatchedAsarPath (Join-Path $TargetAppDir 'resources\app.asar') `
        -RuntimeExecutablePath $targetRuntime
    Write-Ok "Embedded ASAR integrity action: $($asarIntegrityResult.action)"
}
Install-LauncherScript
Install-TaskbarActivator
New-CodexShortcuts $TargetAppDir $sourceAppDir $runtimeExecutableName $runtimeIconRelativePath
Remove-LegacyShortcuts
Save-State $pkg $sourceAppDir $asarIntegrityResult

Write-Step 'Done'
if ($DryRun) {
    Write-Ok 'Dry run completed. No files were changed.'
} else {
    Write-Ok 'Codex RTL is installed.'
    Write-Host 'Desktop shortcuts: Codex RTL, Codex (Original), and ChatGPT'
    Write-Host 'Both shortcuts preserve unknown Codex processes and only stop recognized Desktop app processes.'
}

if ($Launch -and -not $DryRun) {
    $targetRuntime = Resolve-CodexRuntimeExecutable $TargetAppDir
    Start-Process -FilePath $targetRuntime -WorkingDirectory $TargetAppDir
}
