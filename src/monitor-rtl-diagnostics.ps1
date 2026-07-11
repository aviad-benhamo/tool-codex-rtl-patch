<#
.SYNOPSIS
Temporarily captures local diagnostic metadata for the Codex RTL copy.

.DESCRIPTION
Runs in the foreground until Ctrl+C or the configured duration elapses. The
monitor does not launch, stop, or modify Codex. It writes a separate local run
folder containing only operational metadata: RTL process state, installed
versions, relevant Windows application events, and crash-dump metadata.

It deliberately does not collect prompts, conversations, browser cookies,
browser history, page contents, HAR files, command lines, or crash-dump bytes.
#>

param(
    [ValidateRange(1, 480)]
    [int]$DurationMinutes = 120,

    [ValidateRange(5, 60)]
    [int]$PollIntervalSeconds = 10,

    [string]$OutputRoot = (Join-Path $env:LOCALAPPDATA 'OpenAI\CodexRtl\diagnostics')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$installRoot = Join-Path $env:LOCALAPPDATA 'OpenAI\CodexRtl'
$rtlAppDir = Join-Path $installRoot 'app'
$statePath = Join-Path $installRoot 'patch-state.json'
$startedAt = Get-Date
$runId = $startedAt.ToString('yyyyMMdd-HHmmss')
$runDir = Join-Path $OutputRoot "run-$runId"
$eventsPath = Join-Path $runDir 'application-events.jsonl'
$processesPath = Join-Path $runDir 'rtl-processes.jsonl'
$dumpsPath = Join-Path $runDir 'crash-dumps.jsonl'
$contextPath = Join-Path $runDir 'context.json'
$statusPath = Join-Path $runDir 'status.json'
$seenEventIds = [System.Collections.Generic.HashSet[long]]::new()
$seenDumpStates = @{}
$previousProcessState = '__uninitialized__'
$eventCollectionErrorLogged = $false

New-Item -ItemType Directory -Path $runDir -Force | Out-Null

function ConvertTo-RedactedText([string]$Value) {
    if ($null -eq $Value) {
        return $null
    }

    $redacted = $Value.Replace($env:USERPROFILE, '%USERPROFILE%')
    $redacted = [regex]::Replace($redacted, '(?i)(bearer\s+)[^\s]+', '$1[REDACTED]')
    $redacted = [regex]::Replace($redacted, '(?i)(api[_-]?key\s*[:=]\s*)[^\s,;]+', '$1[REDACTED]')
    return $redacted
}

function Write-JsonLine {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Value
    )

    ($Value | ConvertTo-Json -Compress -Depth 5) | Add-Content -LiteralPath $Path -Encoding utf8
}

function Test-UnderPath([string]$Child, [string]$Parent) {
    if (-not $Child -or -not $Parent) {
        return $false
    }

    try {
        $childFull = [System.IO.Path]::GetFullPath($Child).TrimEnd('\\')
        $parentFull = [System.IO.Path]::GetFullPath($Parent).TrimEnd('\\')
    } catch {
        return $false
    }

    return $childFull.Equals($parentFull, [System.StringComparison]::OrdinalIgnoreCase) -or
        $childFull.StartsWith($parentFull + '\\', [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-RtlProcesses {
    if (-not (Test-Path -LiteralPath $rtlAppDir -PathType Container)) {
        return @()
    }

    return @(
        Get-CimInstance Win32_Process -ErrorAction Stop |
            Where-Object {
                $_.ExecutablePath -and
                $_.Name -in @('ChatGPT.exe', 'Codex.exe') -and
                (Test-UnderPath $_.ExecutablePath $rtlAppDir)
            } |
            ForEach-Object {
                [PSCustomObject]@{
                    processId = $_.ProcessId
                    name = $_.Name
                    executablePath = ConvertTo-RedactedText $_.ExecutablePath
                    creationDate = $_.CreationDate
                }
            } |
            Sort-Object processId
    )
}

function Get-OfficialPackageMetadata {
    $pkg = Get-AppxPackage -Name 'OpenAI.Codex' -ErrorAction SilentlyContinue |
        Sort-Object Version -Descending |
        Select-Object -First 1

    if (-not $pkg) {
        return $null
    }

    return [PSCustomObject]@{
        name = $pkg.Name
        version = $pkg.Version.ToString()
        installLocation = ConvertTo-RedactedText $pkg.InstallLocation
    }
}

function Get-PatchStateMetadata {
    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
        return $null
    }

    try {
        $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
        $packageVersion = $null
        $patchedAsarSha256 = $null
        if ($state.PSObject.Properties.Name -contains 'packageVersion') {
            $packageVersion = $state.packageVersion
        }
        if ($state.PSObject.Properties.Name -contains 'patchedAsarSha256') {
            $patchedAsarSha256 = $state.patchedAsarSha256
        }

        return [PSCustomObject]@{
            packageVersion = $packageVersion
            patchedAsarSha256 = $patchedAsarSha256
            updatedAt = (Get-Item -LiteralPath $statePath).LastWriteTime.ToString('o')
        }
    } catch {
        return [PSCustomObject]@{
            packageVersion = $null
            patchedAsarSha256 = $null
            readError = 'patch-state.json could not be parsed.'
            updatedAt = (Get-Item -LiteralPath $statePath).LastWriteTime.ToString('o')
        }
    }
}

function Write-Context {
    $officialPackage = Get-OfficialPackageMetadata
    $patchState = Get-PatchStateMetadata
    $context = [PSCustomObject]@{
        schemaVersion = 1
        runId = $runId
        startedAt = $startedAt.ToString('o')
        monitorDurationMinutes = $DurationMinutes
        pollIntervalSeconds = $PollIntervalSeconds
        rtlAppDir = ConvertTo-RedactedText $rtlAppDir
        officialPackage = $officialPackage
        patchState = $patchState
        versionsMatch = if ($officialPackage -and $patchState -and $officialPackage.version -and $patchState.packageVersion) {
            $officialPackage.version -eq $patchState.packageVersion
        } else {
            $null
        }
        privacy = [PSCustomObject]@{
            excluded = @(
                'prompts and conversations',
                'browser page contents, cookies, and history',
                'browser network traffic and HAR files',
                'process command lines',
                'crash-dump file bytes'
            )
        }
    }
    $context | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $contextPath -Encoding utf8
}

function Write-Status([string]$State, [string]$Reason) {
    [PSCustomObject]@{
        runId = $runId
        state = $State
        reason = $Reason
        updatedAt = (Get-Date).ToString('o')
    } | ConvertTo-Json | Set-Content -LiteralPath $statusPath -Encoding utf8
}

function Capture-RtlProcessState {
    $processes = @(Get-RtlProcesses)
    $stateJson = $processes | ConvertTo-Json -Compress -Depth 4
    if ($stateJson -ne $previousProcessState) {
        Write-JsonLine -Path $processesPath -Value ([PSCustomObject]@{
            capturedAt = (Get-Date).ToString('o')
            processes = $processes
        })
        $script:previousProcessState = $stateJson
    }
}

function Capture-ApplicationEvents {
    try {
        $events = Get-WinEvent -FilterHashtable @{ LogName = 'Application'; StartTime = $startedAt } -ErrorAction Stop |
            Where-Object {
                $_.ProviderName -in @('Application Error', 'Windows Error Reporting') -and
                $_.Message -match '(?i)Codex|ChatGPT'
            }
    } catch {
        if ($_.FullyQualifiedErrorId -like 'NoMatchingEventsFound*') {
            return
        }

        if (-not $script:eventCollectionErrorLogged) {
            Write-JsonLine -Path $eventsPath -Value ([PSCustomObject]@{
                capturedAt = (Get-Date).ToString('o')
                collectionError = ConvertTo-RedactedText $_.Exception.Message
            })
            $script:eventCollectionErrorLogged = $true
        }
        return
    }

    foreach ($event in $events) {
        $recordId = [long]$event.RecordId
        if (-not $seenEventIds.Add($recordId)) {
            continue
        }

        Write-JsonLine -Path $eventsPath -Value ([PSCustomObject]@{
            recordId = $recordId
            timeCreated = $event.TimeCreated.ToString('o')
            providerName = $event.ProviderName
            id = $event.Id
            level = $event.LevelDisplayName
            message = ConvertTo-RedactedText $event.Message
        })
    }
}

function Capture-CrashDumpMetadata {
    $dumpRoot = Join-Path $env:LOCALAPPDATA 'CrashDumps'
    if (-not (Test-Path -LiteralPath $dumpRoot -PathType Container)) {
        return
    }

    Get-ChildItem -LiteralPath $dumpRoot -File -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -match '(?i)Codex|ChatGPT' -and $_.LastWriteTime -ge $startedAt
        } |
        ForEach-Object {
            $stateKey = "{0}|{1}|{2}" -f $_.FullName, $_.Length, $_.LastWriteTimeUtc.Ticks
            if ($seenDumpStates.ContainsKey($stateKey)) {
                return
            }

            $script:seenDumpStates[$stateKey] = $true
            Write-JsonLine -Path $dumpsPath -Value ([PSCustomObject]@{
                capturedAt = (Get-Date).ToString('o')
                name = $_.Name
                path = ConvertTo-RedactedText $_.FullName
                lengthBytes = $_.Length
                lastWriteTime = $_.LastWriteTime.ToString('o')
                copied = $false
            })
        }
}

Write-Context
Write-Status -State 'running' -Reason 'Monitor started.'
Write-Host "RTL diagnostics monitor started. Run folder: $runDir"
Write-Host "It records operational metadata only. Press Ctrl+C to stop."

$deadline = $startedAt.AddMinutes($DurationMinutes)
try {
    while ((Get-Date) -lt $deadline) {
        Capture-RtlProcessState
        Capture-ApplicationEvents
        Capture-CrashDumpMetadata
        Start-Sleep -Seconds $PollIntervalSeconds
    }

    Write-Status -State 'completed' -Reason 'Configured duration elapsed.'
} finally {
    if (Test-Path -LiteralPath $statusPath) {
        $status = Get-Content -LiteralPath $statusPath -Raw | ConvertFrom-Json
        if ($status.state -eq 'running') {
            Write-Status -State 'stopped' -Reason 'Monitor stopped before the configured duration elapsed.'
        }
    }

    Write-Host "RTL diagnostics monitor stopped. Run folder: $runDir"
}
