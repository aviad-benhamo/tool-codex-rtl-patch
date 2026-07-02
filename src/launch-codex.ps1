param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Rtl', 'Original')]
    [string]$Variant
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$installRoot = Join-Path $env:LOCALAPPDATA 'OpenAI\CodexRtl'
$rtlExe = Join-Path $env:LOCALAPPDATA 'OpenAI\CodexRtl\app\Codex.exe'
$statePath = Join-Path $installRoot 'patch-state.json'
$originalShellTarget = 'shell:AppsFolder\OpenAI.Codex_2p2nqsd0c76g0!App'

function Stop-CodexProcesses {
    & taskkill.exe /IM Codex.exe /F 2>$null | Out-Null
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

function Start-Rtl {
    if (-not (Test-Path -LiteralPath $rtlExe -PathType Leaf)) {
        throw "Codex RTL executable was not found: $rtlExe"
    }

    Start-Process -FilePath $rtlExe -WorkingDirectory (Split-Path -Parent $rtlExe)
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
    Stop-CodexProcesses

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
        Start-Rtl
    }
    return $false
}

if ($Variant -eq 'Rtl') {
    if (-not (Confirm-RtlLaunch)) {
        return
    }

    Stop-CodexProcesses
    Start-Rtl
    return
}

Stop-CodexProcesses
Start-Process -FilePath (Join-Path $env:WINDIR 'explorer.exe') -ArgumentList $originalShellTarget
