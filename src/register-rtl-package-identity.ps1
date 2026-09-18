<#
.SYNOPSIS
  Registers a per-user sparse MSIX identity for the local Codex RTL copy.

.DESCRIPTION
  Recent Codex Desktop releases use Windows APIs that require package identity.
  The RTL copy remains outside the official OpenAI MSIX package, so this script
  builds a tiny, locally signed identity package and registers it with the RTL
  app directory as its external location. The official package is never
  modified.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$AppDirectory,
    [Parameter(Mandatory = $true)][string]$StateDirectory,
    [switch]$DryRun,
    [switch]$OutputJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$PackageName = 'CodexRtl.Local'
$ApplicationId = 'App'
$CertificateSubject = 'CN=Codex RTL Local Package'
$PackageVersion = '1.0.0.0'
$RuntimeExecutableName = 'ChatGPT.exe'

function Write-Result([object]$Result) {
    if ($OutputJson) {
        $Result | ConvertTo-Json -Compress
    } else {
        $Result
    }
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Resolve-WindowsSdkTool([string]$ToolName) {
    $command = Get-Command $ToolName -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    $sdkBinRoot = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'
    if (-not (Test-Path -LiteralPath $sdkBinRoot -PathType Container)) {
        throw "Windows SDK tool $ToolName was not found. Install the Windows SDK (Desktop C++ x64 tools) and rerun the installer."
    }

    $versions = Get-ChildItem -LiteralPath $sdkBinRoot -Directory |
        Sort-Object Name -Descending
    foreach ($version in $versions) {
        $candidate = Join-Path $version.FullName "x64\$ToolName"
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }
    }

    throw "Windows SDK tool $ToolName was not found. Install the Windows SDK (Desktop C++ x64 tools) and rerun the installer."
}

function Get-OrCreateSigningCertificate {
    $certificate = Get-ChildItem -Path Cert:\CurrentUser\My |
        Where-Object {
            $_.Subject -eq $CertificateSubject -and
            $_.NotAfter -gt (Get-Date).AddDays(30) -and
            $_.HasPrivateKey
        } |
        Sort-Object NotAfter -Descending |
        Select-Object -First 1

    $created = $false
    if (-not $certificate) {
        $certificate = New-SelfSignedCertificate `
            -Type Custom `
            -Subject $CertificateSubject `
            -KeyUsage DigitalSignature `
            -KeyExportPolicy NonExportable `
            -CertStoreLocation Cert:\CurrentUser\My `
            -NotAfter (Get-Date).AddYears(10) `
            -TextExtension @(
                '2.5.29.19={text}',
                '2.5.29.37={text}1.3.6.1.5.5.7.3.3'
            )
        $created = $true
    }

    $certificatePath = Join-Path $StateDirectory 'codex-rtl-package-identity.cer'
    $trustedStoresAdded = @()
    foreach ($storePath in @('Cert:\LocalMachine\TrustedPeople')) {
        $trustedCertificate = Get-ChildItem -Path $storePath |
            Where-Object { $_.Thumbprint -eq $certificate.Thumbprint } |
            Select-Object -First 1
        if ($trustedCertificate) { continue }

        Export-Certificate -Cert $certificate -FilePath $certificatePath -Force | Out-Null
        Import-Certificate -FilePath $certificatePath -CertStoreLocation $storePath | Out-Null
        $trustedStoresAdded += $storePath
    }

    return [PSCustomObject]@{
        certificate = $certificate
        created = $created
        trustedStoresAdded = $trustedStoresAdded
    }
}

function Write-ApplicationManifest([string]$Path, [string]$Publisher) {
    $manifest = @"
<?xml version="1.0" encoding="utf-8"?>
<assembly manifestVersion="1.0" xmlns="urn:schemas-microsoft-com:asm.v1">
  <assemblyIdentity version="1.0.0.0" name="$PackageName" />
  <msix xmlns="urn:schemas-microsoft-com:msix.v1"
        publisher="$Publisher"
        packageName="$PackageName"
        applicationId="$ApplicationId" />
</assembly>
"@
    $utf8NoBom = New-Object System.Text.UTF8Encoding -ArgumentList $false
    [System.IO.File]::WriteAllText($Path, $manifest, $utf8NoBom)
}

function Write-IdentityPackageManifest([string]$Path, [string]$Publisher) {
    $manifest = @"
<?xml version="1.0" encoding="utf-8"?>
<Package IgnorableNamespaces="uap uap10"
  xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10"
  xmlns:uap="http://schemas.microsoft.com/appx/manifest/uap/windows10"
  xmlns:uap10="http://schemas.microsoft.com/appx/manifest/uap/windows10/10"
  xmlns:rescap="http://schemas.microsoft.com/appx/manifest/foundation/windows10/restrictedcapabilities">
  <Identity Name="$PackageName" Publisher="$Publisher" Version="$PackageVersion" ProcessorArchitecture="neutral" />
  <Properties>
    <DisplayName>Codex RTL</DisplayName>
    <PublisherDisplayName>Codex RTL Local Patch</PublisherDisplayName>
    <Logo>resources\default_app\icon.png</Logo>
    <uap10:AllowExternalContent>true</uap10:AllowExternalContent>
  </Properties>
  <Resources>
    <Resource Language="en-us" />
  </Resources>
  <Dependencies>
    <TargetDeviceFamily Name="Windows.Desktop" MinVersion="10.0.19041.0" MaxVersionTested="10.0.26100.0" />
  </Dependencies>
  <Capabilities>
    <rescap:Capability Name="runFullTrust" />
    <rescap:Capability Name="unvirtualizedResources" />
  </Capabilities>
  <Applications>
    <Application Id="$ApplicationId" Executable="$RuntimeExecutableName" uap10:TrustLevel="mediumIL" uap10:RuntimeBehavior="win32App">
      <uap:VisualElements AppListEntry="none" DisplayName="Codex RTL" Description="Locally patched Codex Desktop" BackgroundColor="transparent" Square150x150Logo="resources\default_app\icon.png" Square44x44Logo="resources\default_app\icon.png" />
    </Application>
  </Applications>
</Package>
"@
    $utf8NoBom = New-Object System.Text.UTF8Encoding -ArgumentList $false
    [System.IO.File]::WriteAllText($Path, $manifest, $utf8NoBom)
}

function Remove-ExistingIdentityPackage {
    $existingPackages = @(Get-AppxPackage -Name $PackageName -ErrorAction SilentlyContinue)
    foreach ($package in $existingPackages) {
        Remove-AppxPackage -Package $package.PackageFullName -ErrorAction Stop
    }
}

if ([Environment]::OSVersion.Version.Build -lt 19041) {
    throw 'Codex RTL package identity requires Windows 10 version 2004 (build 19041) or later.'
}

$runtimePath = Join-Path $AppDirectory $RuntimeExecutableName
if (-not (Test-Path -LiteralPath $runtimePath -PathType Leaf)) {
    throw "Codex RTL runtime was not found: $runtimePath"
}

$identityDirectory = Join-Path $StateDirectory 'package-identity'
$packageLayoutDirectory = Join-Path $identityDirectory 'layout'
$packagePath = Join-Path $identityDirectory 'CodexRtl.Identity.msix'
$applicationManifestPath = "$runtimePath.manifest"

if ($DryRun) {
    $makeAppx = Resolve-WindowsSdkTool 'makeappx.exe'
    $signTool = Resolve-WindowsSdkTool 'signtool.exe'
    Write-Result ([PSCustomObject]@{
        action = 'WouldRegister'
        packageName = $PackageName
        applicationId = $ApplicationId
        appDirectory = $AppDirectory
        packagePath = $packagePath
        applicationManifestPath = $applicationManifestPath
        makeAppxPath = $makeAppx
        signToolPath = $signTool
    })
    return
}

if (-not (Test-IsAdministrator)) {
    throw 'Administrator rights are required to trust the Codex RTL package certificate. Open PowerShell as Administrator and rerun install.ps1.'
}

$makeAppx = Resolve-WindowsSdkTool 'makeappx.exe'
$signTool = Resolve-WindowsSdkTool 'signtool.exe'
New-Item -ItemType Directory -Force $identityDirectory | Out-Null
if (Test-Path -LiteralPath $packageLayoutDirectory) {
    Remove-Item -LiteralPath $packageLayoutDirectory -Recurse -Force
}
New-Item -ItemType Directory -Force $packageLayoutDirectory | Out-Null

$certificateRecord = $null
try {
    $certificateRecord = Get-OrCreateSigningCertificate
    $certificate = $certificateRecord.certificate
    Write-ApplicationManifest $applicationManifestPath $certificate.Subject
    Write-IdentityPackageManifest (Join-Path $packageLayoutDirectory 'AppxManifest.xml') $certificate.Subject

    & $makeAppx pack /o /d $packageLayoutDirectory /nv /p $packagePath | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'makeappx.exe failed to build the Codex RTL identity package.' }

    & $signTool sign /fd SHA256 /sha1 $certificate.Thumbprint /s My $packagePath | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'signtool.exe failed to sign the Codex RTL identity package.' }

    Remove-ExistingIdentityPackage
    Add-AppxPackage -Path $packagePath -ExternalLocation $AppDirectory -ErrorAction Stop
    $registeredPackage = Get-AppxPackage -Name $PackageName -ErrorAction Stop |
        Sort-Object Version -Descending |
        Select-Object -First 1
    if (-not $registeredPackage) {
        throw 'Codex RTL identity package registration did not return a package.'
    }

    Write-Result ([PSCustomObject]@{
        action = 'Registered'
        packageName = $PackageName
        packageFullName = $registeredPackage.PackageFullName
        packageFamilyName = $registeredPackage.PackageFamilyName
        appUserModelId = "$($registeredPackage.PackageFamilyName)!$ApplicationId"
        certificateThumbprint = $certificate.Thumbprint
        applicationManifestPath = $applicationManifestPath
        packagePath = $packagePath
    })
} catch {
    if ($certificateRecord) {
        foreach ($storePath in @($certificateRecord.trustedStoresAdded)) {
            Remove-Item -LiteralPath (Join-Path $storePath $certificateRecord.certificate.Thumbprint) -Force -ErrorAction SilentlyContinue
        }
    }
    if ($certificateRecord -and $certificateRecord.created) {
        Remove-Item -LiteralPath (Join-Path Cert:\CurrentUser\My $certificateRecord.certificate.Thumbprint) -Force -ErrorAction SilentlyContinue
    }
    throw
}
