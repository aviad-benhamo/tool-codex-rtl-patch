param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Rtl', 'Original')]
    [string]$Variant
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$installRoot = Join-Path $env:LOCALAPPDATA 'OpenAI\CodexRtl'
$rtlAppDir = Join-Path $installRoot 'app'
$statePath = Join-Path $installRoot 'patch-state.json'
$originalShellTarget = 'shell:AppsFolder\OpenAI.Codex_2p2nqsd0c76g0!App'

function Resolve-FullPath([string]$Path) {
    if (-not $Path) {
        return $null
    }

    try {
        return [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
    } catch {
        return $null
    }
}

function Test-UnderPath([string]$Child, [string]$Parent) {
    $childFull = Resolve-FullPath $Child
    $parentFull = Resolve-FullPath $Parent

    if (-not $childFull -or -not $parentFull) {
        return $false
    }

    return $childFull.Equals($parentFull, [System.StringComparison]::OrdinalIgnoreCase) -or
        $childFull.StartsWith($parentFull + '\', [System.StringComparison]::OrdinalIgnoreCase)
}

function Add-UniquePath {
    param(
        [Parameter(Mandatory = $true)][ref]$Paths,
        [string]$Path
    )

    $fullPath = Resolve-FullPath $Path
    if (-not $fullPath) {
        return
    }

    foreach ($existingPath in $Paths.Value) {
        if ($existingPath.Equals($fullPath, [System.StringComparison]::OrdinalIgnoreCase)) {
            return
        }
    }

    $Paths.Value += $fullPath
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

function Get-CodexDesktopAppDirs {
    $appDirs = @()

    if (Test-Path -LiteralPath $rtlAppDir -PathType Container) {
        Add-UniquePath ([ref]$appDirs) $rtlAppDir
    }

    $pkg = Get-CodexPackage
    if ($pkg -and $pkg.InstallLocation) {
        $originalAppDir = Join-Path $pkg.InstallLocation 'app'
        if (Test-Path -LiteralPath $originalAppDir -PathType Container) {
            Add-UniquePath ([ref]$appDirs) $originalAppDir
        }
    }

    return $appDirs
}

function Get-CodexDesktopProcesses {
    $desktopAppDirs = @(Get-CodexDesktopAppDirs)
    if ($desktopAppDirs.Count -eq 0) {
        return @()
    }

    $runtimeExecutableNames = @('ChatGPT.exe', 'Codex.exe')
    $processes = Get-CimInstance Win32_Process |
        Where-Object {
            $_.ExecutablePath -and
            ($runtimeExecutableNames -contains $_.Name)
        }

    foreach ($process in $processes) {
        foreach ($desktopAppDir in $desktopAppDirs) {
            if (Test-UnderPath ([string]$process.ExecutablePath) $desktopAppDir) {
                $process
                break
            }
        }
    }
}

function Stop-CodexDesktopProcesses {
    # Do not stop Codex by process name. VS Code Codex also runs codex.exe, so only
    # positively identified Desktop processes under known app directories are safe.
    $processes = @(Get-CodexDesktopProcesses)
    foreach ($process in $processes) {
        Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
    }

    Start-Sleep -Seconds 2
}

function Get-CodexPackage {
    $pkg = Get-AppxPackage -Name 'OpenAI.Codex' -ErrorAction SilentlyContinue |
        Sort-Object Version -Descending |
        Select-Object -First 1
    if ($pkg -and $pkg.InstallLocation) {
        return $pkg
    }
    return $null
}

function Read-PatchState {
    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
        return $null
    }

    try {
        return Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    } catch {
        return $null
    }
}

function Show-MessageBox([string]$Message, [string]$Title, [string]$Buttons, [string]$Icon) {
    Add-Type -AssemblyName System.Windows.Forms
    $buttonValue = [System.Enum]::Parse([System.Windows.Forms.MessageBoxButtons], $Buttons)
    $iconValue = [System.Enum]::Parse([System.Windows.Forms.MessageBoxIcon], $Icon)
    return [System.Windows.Forms.MessageBox]::Show(
        $Message,
        $Title,
        $buttonValue,
        $iconValue
    )
}

function Test-InstallerScript([string]$ScriptPath) {
    if (-not $ScriptPath) {
        return $false
    }

    if (-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) {
        return $false
    }

    $repoDir = Split-Path -Parent $ScriptPath
    $requiredPaths = @(
        (Join-Path $repoDir 'src\codex-rtl-patch.js'),
        (Join-Path $repoDir 'src\update-asar-integrity.ps1'),
        (Join-Path $repoDir 'src\register-rtl-package-identity.ps1'),
        (Join-Path $repoDir 'src\launch-codex.ps1')
    )

    foreach ($requiredPath in $requiredPaths) {
        if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
            return $false
        }
    }

    return $true
}

function Add-UniqueCandidate {
    param(
        [Parameter(Mandatory = $true)][ref]$Candidates,
        [string]$Path
    )

    if (-not $Path) {
        return
    }

    $trimmedPath = $Path.Trim()
    if (-not $trimmedPath) {
        return
    }

    foreach ($candidate in $Candidates.Value) {
        if ($candidate.Equals($trimmedPath, [System.StringComparison]::OrdinalIgnoreCase)) {
            return
        }
    }

    $Candidates.Value += $trimmedPath
}

function Add-RepoInstallCandidates {
    param(
        [Parameter(Mandatory = $true)][ref]$Candidates,
        [string]$RepoDir
    )

    if (-not $RepoDir) {
        return
    }

    Add-UniqueCandidate -Candidates $Candidates -Path (Join-Path $RepoDir 'install.ps1')

    $parentDir = Split-Path -Parent $RepoDir
    if (-not $parentDir -or -not (Test-Path -LiteralPath $parentDir -PathType Container)) {
        return
    }

    foreach ($repoName in @('tool-codex-rtl-patch', 'codex-desktop-rtl-patch')) {
        Add-UniqueCandidate -Candidates $Candidates -Path (Join-Path (Join-Path $parentDir $repoName) 'install.ps1')
    }
}

function Resolve-InstallerScriptPath([object]$State) {
    $candidates = @()

    if ($State -and ($State.PSObject.Properties.Name -contains 'installerScriptPath')) {
        Add-UniqueCandidate ([ref]$candidates) ([string]$State.installerScriptPath)
        $installerRepoDir = Split-Path -Parent ([string]$State.installerScriptPath)
        Add-RepoInstallCandidates ([ref]$candidates) $installerRepoDir
    }

    if ($State -and ($State.PSObject.Properties.Name -contains 'repositoryDir')) {
        Add-RepoInstallCandidates ([ref]$candidates) ([string]$State.repositoryDir)
    }

    foreach ($candidate in $candidates) {
        if (Test-InstallerScript $candidate) {
            return [System.IO.Path]::GetFullPath($candidate)
        }
    }

    return $null
}

function Update-PatchStateInstallerPath([object]$State, [string]$InstallerScriptPath) {
    if (-not $State -or -not $InstallerScriptPath) {
        return
    }

    $installerScriptFullPath = [System.IO.Path]::GetFullPath($InstallerScriptPath)
    $repositoryDir = Split-Path -Parent $installerScriptFullPath
    $changed = $false

    if (-not ($State.PSObject.Properties.Name -contains 'installerScriptPath')) {
        $State | Add-Member -NotePropertyName installerScriptPath -NotePropertyValue $installerScriptFullPath
        $changed = $true
    } elseif ([string]$State.installerScriptPath -ne $installerScriptFullPath) {
        $State.installerScriptPath = $installerScriptFullPath
        $changed = $true
    }

    if (-not ($State.PSObject.Properties.Name -contains 'repositoryDir')) {
        $State | Add-Member -NotePropertyName repositoryDir -NotePropertyValue $repositoryDir
        $changed = $true
    } elseif ([string]$State.repositoryDir -ne $repositoryDir) {
        $State.repositoryDir = $repositoryDir
        $changed = $true
    }

    if (-not $changed) {
        return
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding -ArgumentList $false
    $json = $State | ConvertTo-Json -Depth 5
    [System.IO.File]::WriteAllText($statePath, $json + "`n", $utf8NoBom)
}

function Save-LastSelectedVariant([string]$Variant) {
    $state = Read-PatchState
    if (-not $state -or $Variant -notin @('Rtl', 'Original')) {
        return
    }

    if (-not ($state.PSObject.Properties.Name -contains 'lastSelectedVariant')) {
        $state | Add-Member -NotePropertyName lastSelectedVariant -NotePropertyValue $Variant
    } else {
        $state.lastSelectedVariant = $Variant
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding -ArgumentList $false
    $json = $state | ConvertTo-Json -Depth 5
    [System.IO.File]::WriteAllText($statePath, $json + "`n", $utf8NoBom)
}

function Get-RtlShellTarget([object]$State) {
    if (-not $State -or -not ($State.PSObject.Properties.Name -contains 'rtlAppUserModelId')) {
        return $null
    }

    $appUserModelId = [string]$State.rtlAppUserModelId
    if (-not $appUserModelId -or $appUserModelId -notmatch '^[^!]+!App$') {
        return $null
    }

    return "shell:AppsFolder\$appUserModelId"
}

function Start-Rtl([object]$State) {
    $rtlShellTarget = Get-RtlShellTarget $State
    if (-not $rtlShellTarget) {
        throw 'Codex RTL package identity is missing. Re-run install.ps1 before launching the patched copy.'
    }

    Start-Process -FilePath (Join-Path $env:WINDIR 'explorer.exe') -ArgumentList $rtlShellTarget
}

function Invoke-RtlRebuild([object]$State) {
    $installerScriptPath = Resolve-InstallerScriptPath $State

    if (-not $installerScriptPath) {
        $manual = @"
Codex RTL cannot rebuild automatically because the reviewed local installer path is not available.

From your local repository clone, run:

powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
"@
        Show-MessageBox $manual 'Codex RTL rebuild path missing' 'OK' 'Warning' | Out-Null
        return $false
    }

    Update-PatchStateInstallerPath $State $installerScriptPath
    Stop-CodexDesktopProcesses

    $powershellPath = Join-Path $PSHOME 'powershell.exe'
    $installerArguments = "-NoProfile -ExecutionPolicy Bypass -File `"$installerScriptPath`""
    $proc = Start-Process `
        -FilePath $powershellPath `
        -ArgumentList $installerArguments `
        -Wait `
        -PassThru

    if ($proc.ExitCode -ne 0) {
        $message = "Codex RTL rebuild failed with exit code $($proc.ExitCode). The existing RTL copy was left in place."
        Show-MessageBox $message 'Codex RTL rebuild failed' 'OK' 'Error' | Out-Null
        return $false
    }

    return $true
}

function Test-RtlStale([object]$Package, [object]$State) {
    if (-not $Package -or -not $State) {
        return $true
    }

    if (-not ($State.PSObject.Properties.Name -contains 'packageVersion')) {
        return $true
    }

    return ([string]$Package.Version -ne [string]$State.packageVersion)
}

function Confirm-RtlLaunch {
    $pkg = Get-CodexPackage
    $state = Read-PatchState
    if (-not (Test-RtlStale $pkg $state)) {
        return $true
    }

    $officialVersion = if ($pkg) { [string]$pkg.Version } else { 'not found' }
    $rtlVersion = if ($state -and ($state.PSObject.Properties.Name -contains 'packageVersion')) {
        [string]$state.packageVersion
    } else {
        'unknown'
    }

    $message = @"
Codex was updated or the RTL install state is missing.

Official Codex: $officialVersion
RTL copy: $rtlVersion

The RTL copy may show outdated model labels or behave differently from the official app until it is rebuilt.

Select Yes to rebuild RTL now.
Select No to continue launching the stale RTL copy.
Select Cancel to stop.
"@

    $choice = Show-MessageBox $message 'Codex RTL copy may be stale' 'YesNoCancel' 'Warning'
    if ($choice -eq [System.Windows.Forms.DialogResult]::Cancel) {
        return $false
    }

    if ($choice -eq [System.Windows.Forms.DialogResult]::No) {
        return $true
    }

    if (Invoke-RtlRebuild $state) {
        Start-Rtl (Read-PatchState)
    }
    return $false
}

if ($Variant -eq 'Rtl') {
    if (-not (Confirm-RtlLaunch)) {
        return
    }

    Save-LastSelectedVariant $Variant
    Stop-CodexDesktopProcesses
    Start-Rtl (Read-PatchState)
    return
}

Save-LastSelectedVariant $Variant
Stop-CodexDesktopProcesses
Start-Process -FilePath (Join-Path $env:WINDIR 'explorer.exe') -ArgumentList $originalShellTarget
