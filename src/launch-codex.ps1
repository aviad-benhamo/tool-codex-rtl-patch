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

function Start-Rtl {
    if (-not (Test-Path -LiteralPath $rtlExe -PathType Leaf)) {
        throw "Codex RTL executable was not found: $rtlExe"
    }

    Start-Process -FilePath $rtlExe -WorkingDirectory (Split-Path -Parent $rtlExe)
}

function Invoke-RtlRebuild([object]$State) {
    $installerScriptPath = $null
    if ($State -and ($State.PSObject.Properties.Name -contains 'installerScriptPath')) {
        $installerScriptPath = [string]$State.installerScriptPath
    }

    if (-not $installerScriptPath -or -not (Test-Path -LiteralPath $installerScriptPath -PathType Leaf)) {
        $manual = @"
Codex RTL cannot rebuild automatically because the reviewed local installer path is not available.

From your local repository clone, run:

powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
"@
        Show-MessageBox $manual 'Codex RTL rebuild path missing' 'OK' 'Warning' | Out-Null
        return $false
    }

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
