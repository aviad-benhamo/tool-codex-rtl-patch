param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Rtl', 'Original')]
    [string]$Variant
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$rtlExe = Join-Path $env:LOCALAPPDATA 'OpenAI\CodexRtl\app\Codex.exe'
$originalShellTarget = 'shell:AppsFolder\OpenAI.Codex_2p2nqsd0c76g0!App'

& taskkill.exe /IM Codex.exe /F 2>$null | Out-Null
Start-Sleep -Seconds 2

if ($Variant -eq 'Rtl') {
    if (-not (Test-Path -LiteralPath $rtlExe -PathType Leaf)) {
        throw "Codex RTL executable was not found: $rtlExe"
    }

    Start-Process -FilePath $rtlExe -WorkingDirectory (Split-Path -Parent $rtlExe)
    return
}

Start-Process -FilePath (Join-Path $env:WINDIR 'explorer.exe') -ArgumentList $originalShellTarget
