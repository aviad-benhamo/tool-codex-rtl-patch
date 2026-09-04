<#
.SYNOPSIS
  Updates the embedded Electron ASAR header hash in a copied Windows runtime.

.DESCRIPTION
  Newer Electron builds can enable embedded ASAR integrity validation. On
  Windows, the expected app.asar header hash is stored in the runtime PE
  resource as a fixed-length hexadecimal value. Repacking app.asar changes the
  header hash, so a copied runtime exits with a fatal integrity error unless the
  copied executable is updated to expect the patched archive.

  This script replaces only the unique original header hash with the patched
  header hash. It does not disable Electron's integrity fuse and never modifies
  the official runtime executable.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SourceAsarPath,
    [Parameter(Mandatory = $true)][string]$PatchedAsarPath,
    [Parameter(Mandatory = $true)][string]$RuntimeExecutablePath,
    [switch]$DryRun,
    [switch]$OutputJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-AsarHeaderSha256([string]$AsarPath) {
    if (-not (Test-Path -LiteralPath $AsarPath -PathType Leaf)) {
        throw "ASAR archive was not found: $AsarPath"
    }

    $stream = [System.IO.File]::OpenRead($AsarPath)
    try {
        $sizePickle = New-Object byte[] 8
        if ($stream.Read($sizePickle, 0, $sizePickle.Length) -ne $sizePickle.Length) {
            throw "Could not read the ASAR size pickle: $AsarPath"
        }

        $headerPickleSize = [BitConverter]::ToUInt32($sizePickle, 4)
        if ($headerPickleSize -lt 8 -or $headerPickleSize -gt $stream.Length - 8) {
            throw "Invalid ASAR header pickle size in: $AsarPath"
        }

        $headerPickle = New-Object byte[] $headerPickleSize
        if ($stream.Read($headerPickle, 0, $headerPickle.Length) -ne $headerPickle.Length) {
            throw "Could not read the ASAR header pickle: $AsarPath"
        }

        $headerStringSize = [BitConverter]::ToUInt32($headerPickle, 4)
        if ($headerStringSize -gt $headerPickle.Length - 8) {
            throw "Invalid ASAR header string size in: $AsarPath"
        }

        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        try {
            $hashBytes = $sha256.ComputeHash($headerPickle, 8, $headerStringSize)
            return ([BitConverter]::ToString($hashBytes)).Replace('-', '').ToLowerInvariant()
        } finally {
            $sha256.Dispose()
        }
    } finally {
        $stream.Dispose()
    }
}

function Get-OccurrenceIndexes([string]$Text, [string]$Value) {
    $indexes = @()
    $startIndex = 0
    while ($startIndex -lt $Text.Length) {
        $index = $Text.IndexOf($Value, $startIndex, [StringComparison]::OrdinalIgnoreCase)
        if ($index -lt 0) { break }
        $indexes += $index
        $startIndex = $index + $Value.Length
    }
    return $indexes
}

function Write-Result([object]$Result) {
    if ($OutputJson) {
        $Result | ConvertTo-Json -Compress
    } else {
        $Result
    }
}

if (-not (Test-Path -LiteralPath $RuntimeExecutablePath -PathType Leaf)) {
    throw "Runtime executable was not found: $RuntimeExecutablePath"
}

$sourceHeaderHash = Get-AsarHeaderSha256 $SourceAsarPath
$patchedHeaderHash = Get-AsarHeaderSha256 $PatchedAsarPath
$runtimeBytes = [System.IO.File]::ReadAllBytes($RuntimeExecutablePath)
$runtimeText = [System.Text.Encoding]::ASCII.GetString($runtimeBytes)
$sourceHashIndexes = @(Get-OccurrenceIndexes $runtimeText $sourceHeaderHash)
$patchedHashIndexes = @(Get-OccurrenceIndexes $runtimeText $patchedHeaderHash)
$integrityMarker = '"file":"resources\\app.asar"'
$hasIntegrityMarker = $runtimeText.IndexOf(
    $integrityMarker,
    [StringComparison]::OrdinalIgnoreCase
) -ge 0

$action = 'NotRequired'
if ($sourceHeaderHash -eq $patchedHeaderHash) {
    $action = 'ArchiveUnchanged'
} elseif (
    $hasIntegrityMarker -and
    $sourceHashIndexes.Count -eq 1 -and
    $patchedHashIndexes.Count -eq 0
) {
    $action = if ($DryRun) { 'WouldUpdate' } else { 'Updated' }
    if (-not $DryRun) {
        $replacementBytes = [System.Text.Encoding]::ASCII.GetBytes($patchedHeaderHash)
        [Array]::Copy(
            $replacementBytes,
            0,
            $runtimeBytes,
            $sourceHashIndexes[0],
            $replacementBytes.Length
        )
        [System.IO.File]::WriteAllBytes($RuntimeExecutablePath, $runtimeBytes)

        $verifiedText = [System.Text.Encoding]::ASCII.GetString(
            [System.IO.File]::ReadAllBytes($RuntimeExecutablePath)
        )
        $verifiedSourceCount = @(Get-OccurrenceIndexes $verifiedText $sourceHeaderHash).Count
        $verifiedPatchedCount = @(Get-OccurrenceIndexes $verifiedText $patchedHeaderHash).Count
        if ($verifiedSourceCount -ne 0 -or $verifiedPatchedCount -ne 1) {
            throw "Embedded ASAR integrity update verification failed: $RuntimeExecutablePath"
        }
    }
} elseif ($sourceHashIndexes.Count -eq 0 -and $patchedHashIndexes.Count -eq 1) {
    $action = 'AlreadyUpdated'
} elseif (-not $hasIntegrityMarker -and $sourceHashIndexes.Count -eq 0) {
    $action = 'IntegrityMetadataNotPresent'
} else {
    throw "Could not safely identify the embedded ASAR integrity hash in: $RuntimeExecutablePath. Source hash matches: $($sourceHashIndexes.Count); patched hash matches: $($patchedHashIndexes.Count); integrity marker present: $hasIntegrityMarker"
}

$result = [PSCustomObject]@{
    action = $action
    sourceAsarHeaderSha256 = $sourceHeaderHash
    patchedAsarHeaderSha256 = $patchedHeaderHash
    runtimeExecutablePath = $RuntimeExecutablePath
}
Write-Result $result
