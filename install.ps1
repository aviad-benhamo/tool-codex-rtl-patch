<# 
.SYNOPSIS
  Installs a local RTL-enabled copy of Codex Desktop.

.DESCRIPTION
  This installer does not modify the Microsoft Store/MSIX package under
  WindowsApps. It copies the Codex app folder to LocalAppData, patches the
  copied app.asar, and creates separate desktop shortcuts for the patched RTL
  copy and the original Microsoft Store application.
#>
param(
    [switch]$DryRun,
    [switch]$Launch
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
$RtlLauncherShortcutPath = Join-Path $DesktopPath 'Launch Codex RTL.lnk'
$OriginalLauncherShortcutPath = Join-Path $DesktopPath 'Launch Codex Original.lnk'
$ExplorerPath = Join-Path $env:WINDIR 'explorer.exe'
$PowerShellPath = Join-Path $PSHOME 'powershell.exe'
$OriginalAppUserModelId = 'OpenAI.Codex_2p2nqsd0c76g0!App'
$OriginalShellTarget = "shell:AppsFolder\$OriginalAppUserModelId"
$ScriptPath = $MyInvocation.MyCommand.Path
$ThisDir = if ($ScriptPath) { Split-Path -Parent $ScriptPath } else { (Get-Location).Path }
$PatchJsSource = Join-Path $ThisDir 'src\codex-rtl-patch.js'
$LauncherScriptSource = Join-Path $ThisDir 'src\launch-codex.ps1'
$LauncherScriptPath = Join-Path $InstallRoot 'launch-codex.ps1'

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

function Assert-LocalLauncherScript {
    if (-not (Test-Path -LiteralPath $LauncherScriptSource -PathType Leaf)) {
        throw "Required launcher script was not found: $LauncherScriptSource"
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

function Patch-Asar([string]$AppDir, [string]$Npx) {
    $asarPath = Join-Path $AppDir 'resources\app.asar'
    if ((-not $DryRun) -and (-not (Test-Path -LiteralPath $asarPath))) {
        throw "app.asar was not found in target app: $asarPath"
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
            Write-Host "DRY RUN $Npx --yes $AsarPackage pack `"$tempRoot`" `"$asarPath`""
        } else {
            & $Npx --yes $AsarPackage pack $tempRoot $asarPath
            if ($LASTEXITCODE -ne 0) { throw 'asar pack failed' }
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
    Write-Ok "Created shortcut: $ShortcutPath"
}

function New-CodexShortcuts([string]$RtlAppDir, [string]$OriginalAppDir) {
    $rtlExe = Join-Path $RtlAppDir 'Codex.exe'
    $rtlIcon = Join-Path $RtlAppDir 'resources\icon.ico'
    $originalIcon = Join-Path $OriginalAppDir 'resources\icon.ico'

    New-WindowsShortcut `
        -ShortcutPath $RtlShortcutPath `
        -TargetPath $rtlExe `
        -WorkingDirectory $RtlAppDir `
        -IconLocation $rtlIcon `
        -Description 'Codex Desktop with local RTL patch'

    New-WindowsShortcut `
        -ShortcutPath $OriginalShortcutPath `
        -TargetPath $ExplorerPath `
        -Arguments $OriginalShellTarget `
        -WorkingDirectory (Split-Path -Parent $ExplorerPath) `
        -IconLocation $originalIcon `
        -Description 'Original Microsoft Store Codex Desktop'

    $launcherBaseArguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$LauncherScriptPath`""

    New-WindowsShortcut `
        -ShortcutPath $RtlLauncherShortcutPath `
        -TargetPath $PowerShellPath `
        -Arguments "$launcherBaseArguments -Variant Rtl" `
        -WorkingDirectory $InstallRoot `
        -IconLocation $rtlIcon `
        -Description 'Stop running Codex processes and launch Codex RTL'

    New-WindowsShortcut `
        -ShortcutPath $OriginalLauncherShortcutPath `
        -TargetPath $PowerShellPath `
        -Arguments "$launcherBaseArguments -Variant Original" `
        -WorkingDirectory $InstallRoot `
        -IconLocation $originalIcon `
        -Description 'Stop running Codex processes and launch original Codex'
}

function Save-State([object]$Package, [string]$SourceAppDir) {
    if ($DryRun) { return }
    New-Item -ItemType Directory -Force $InstallRoot | Out-Null
    $state = [ordered]@{
        patchVersion = $PatchVersion
        installedAt = (Get-Date).ToString('o')
        packageName = $Package.Name
        packageVersion = [string]$Package.Version
        packageInstallLocation = $Package.InstallLocation
        sourceAppDir = $SourceAppDir
        targetAppDir = $TargetAppDir
    }
    $json = $state | ConvertTo-Json -Depth 5
    $utf8NoBom = New-Object System.Text.UTF8Encoding -ArgumentList $false
    [System.IO.File]::WriteAllText($StatePath, $json + "`n", $utf8NoBom)
}

Write-Step 'Checking local patch file'
Assert-LocalPatchFile
Write-Ok "Using local patch: $PatchJsSource"
Assert-LocalLauncherScript
Write-Ok "Using local launcher script: $LauncherScriptSource"

Write-Step 'Finding installed Codex'
$pkg = Get-CodexPackage
$sourceAppDir = Join-Path $pkg.InstallLocation 'app'
$sourceAsar = Join-Path $sourceAppDir 'resources\app.asar'
if (-not (Test-Path -LiteralPath $sourceAsar)) {
    throw "Installed Codex app.asar was not found: $sourceAsar"
}
Write-Ok "Found Codex $($pkg.Version)"
Write-Host "Source: $sourceAppDir"

Write-Step 'Checking tools'
$npx = Get-NpxCommand
Write-Ok "Using npx: $npx"

Assert-UnderPath $TargetAppDir $InstallRoot

Write-Step 'Copying Codex to a local patchable folder'
Write-Host "Target: $TargetAppDir"
Invoke-RobocopyMirror $sourceAppDir $TargetAppDir

Patch-Asar $TargetAppDir $npx
Install-LauncherScript
New-CodexShortcuts $TargetAppDir $sourceAppDir
Save-State $pkg $sourceAppDir

Write-Step 'Done'
if ($DryRun) {
    Write-Ok 'Dry run completed. No files were changed.'
} else {
    Write-Ok 'Codex RTL is installed.'
    Write-Host 'Desktop shortcuts: Codex RTL, Codex (Original), Launch Codex RTL, and Launch Codex Original'
    Write-Host 'Use the Launch shortcuts to switch variants without manually stopping Codex processes.'
}

if ($Launch -and -not $DryRun) {
    Start-Process -FilePath (Join-Path $TargetAppDir 'Codex.exe') -WorkingDirectory $TargetAppDir
}
