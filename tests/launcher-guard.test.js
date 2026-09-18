const assert = require("node:assert/strict");
const childProcess = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");

const repoRoot = path.join(__dirname, "..");
const launcher = fs.readFileSync(
  path.join(repoRoot, "src", "launch-codex.ps1"),
  "utf8"
);
const installer = fs.readFileSync(path.join(repoRoot, "install.ps1"), "utf8");
const rtlPatch = fs.readFileSync(
  path.join(repoRoot, "src", "codex-rtl-patch.js"),
  "utf8"
);

assert.doesNotMatch(launcher, /StopExisting/);
assert.match(launcher, /Get-AppxPackage -Name 'OpenAI\.Codex'/);
assert.match(launcher, /function Resolve-CodexRuntimeExecutable/);
assert.match(
  launcher,
  /foreach \(\$executableName in @\('ChatGPT\.exe', 'Codex\.exe'\)\)/
);
assert.match(
  launcher,
  /No supported Codex Desktop runtime executable was found in:/
);

const runtimeResolverStart = launcher.indexOf(
  "function Resolve-CodexRuntimeExecutable"
);
const runtimeResolverEnd = launcher.indexOf(
  "\nfunction Get-CodexDesktopAppDirs",
  runtimeResolverStart
);
assert.notEqual(runtimeResolverStart, -1, "Could not locate runtime resolver");
assert.notEqual(runtimeResolverEnd, -1, "Could not delimit runtime resolver");

const runtimeResolver = launcher.slice(runtimeResolverStart, runtimeResolverEnd);
const runtimeResolverTest = `
$ErrorActionPreference = 'Stop'
${runtimeResolver}
function Test-Path {
    param([string]$LiteralPath, [string]$PathType)
    return $script:runtimePaths -contains $LiteralPath
}

$runtimeDir = 'C:\\runtime'
$script:runtimePaths = @('C:\\runtime\\ChatGPT.exe', 'C:\\runtime\\Codex.exe')
if ((Resolve-CodexRuntimeExecutable $runtimeDir) -ne 'C:\\runtime\\ChatGPT.exe') {
    throw 'ChatGPT.exe was not preferred over Codex.exe.'
}

$script:runtimePaths = @('C:\\runtime\\Codex.exe')
if ((Resolve-CodexRuntimeExecutable $runtimeDir) -ne 'C:\\runtime\\Codex.exe') {
    throw 'Codex.exe fallback was not selected.'
}

$script:runtimePaths = @()
try {
    Resolve-CodexRuntimeExecutable $runtimeDir | Out-Null
    throw 'Resolver did not fail when no runtime executable existed.'
} catch {
    if ($_.Exception.Message -notmatch 'Expected ChatGPT.exe or Codex.exe') {
        throw
    }
}
`;
const runtimeResolverResult = childProcess.spawnSync(
  "powershell.exe",
  ["-NoProfile", "-Command", "-"],
  { encoding: "utf8", input: runtimeResolverTest }
);
assert.equal(
  runtimeResolverResult.status,
  0,
  runtimeResolverResult.stderr || runtimeResolverResult.stdout
);
assert.match(launcher, /\$statePath = Join-Path \$installRoot 'patch-state\.json'/);
assert.match(launcher, /packageVersion/);
assert.match(launcher, /installerScriptPath/);
assert.match(launcher, /function Resolve-InstallerScriptPath/);
assert.match(launcher, /function Update-PatchStateInstallerPath/);
assert.match(launcher, /tool-codex-rtl-patch/);
assert.match(launcher, /function Confirm-RtlLaunch/);
assert.match(launcher, /Select Yes to rebuild RTL now\./);
assert.match(launcher, /Select No to continue launching the stale RTL copy\./);
assert.match(launcher, /Invoke-RtlRebuild/);
assert.doesNotMatch(launcher, /taskkill\.exe\s+\/IM\s+Codex\.exe\s+\/F/i);
assert.doesNotMatch(launcher, /Stop-Process\s+-Name\s+Codex/i);
assert.doesNotMatch(launcher, /\\.vscode\\extensions/i);
assert.match(launcher, /function Get-CodexDesktopAppDirs/);
assert.match(launcher, /function Get-CodexDesktopProcesses/);
assert.match(launcher, /Get-CimInstance Win32_Process/);
assert.match(launcher, /ExecutablePath/);
assert.match(launcher, /\$runtimeExecutableNames = @\('ChatGPT\.exe', 'Codex\.exe'\)/);
assert.match(launcher, /\$runtimeExecutableNames -contains \$_\.Name/);
assert.match(launcher, /function Test-UnderPath/);
assert.match(launcher, /Stop-Process -Id \$process\.ProcessId -Force/);
assert.match(launcher, /Stop-CodexDesktopProcesses\s*\r?\n\s*Start-Rtl/);
assert.match(launcher, /Stop-CodexDesktopProcesses\s*\r?\nStart-Process -FilePath \(Join-Path \$env:WINDIR 'explorer\.exe'\)/);

assert.match(
  installer,
  /-ShortcutPath \$RtlShortcutPath\s+`\r?\n\s+-TargetPath \$PowerShellPath\s+`\r?\n\s+-Arguments "\$launcherBaseArguments -Variant Rtl"/
);
assert.match(
  installer,
  /-ShortcutPath \$OriginalShortcutPath\s+`\r?\n\s+-TargetPath \$PowerShellPath\s+`\r?\n\s+-Arguments "\$launcherBaseArguments -Variant Original"/
);
assert.doesNotMatch(installer, /RtlLauncherShortcutPath|OriginalLauncherShortcutPath/);
assert.doesNotMatch(installer, /-Variant Rtl -StopExisting|-Variant Original -StopExisting/);
assert.doesNotMatch(installer, /Stop running Codex processes/i);
assert.doesNotMatch(installer, /stop existing Codex processes/i);
assert.match(installer, /Remove-LegacyShortcuts/);
assert.match(installer, /installerScriptPath = \$ScriptPath/);
assert.match(installer, /repositoryDir = \$ThisDir/);
assert.match(installer, /function Resolve-CodexRuntimeExecutable/);
assert.match(
  installer,
  /foreach \(\$executableName in @\('ChatGPT\.exe', 'Codex\.exe'\)\)/
);
assert.match(
  installer,
  /No supported Codex Desktop runtime executable was found in:/
);
assert.match(installer, /\$sourceRuntime = Resolve-CodexRuntimeExecutable \$sourceAppDir/);
assert.match(installer, /\$targetRuntime = Resolve-CodexRuntimeExecutable \$TargetAppDir/);
assert.match(
  installer,
  /Start-Process -FilePath \$ExplorerPath -ArgumentList "shell:AppsFolder\\\$\(\$packageIdentityResult\.appUserModelId\)"/
);
assert.match(installer, /resources\\icon-chatgpt\.ico', 'resources\\icon\.ico/);
assert.match(installer, /function Get-AsarUnpackedEntries/);
assert.match(installer, /list --is-pack/);
assert.match(installer, /function Get-AsarUnpackPatterns/);
assert.match(installer, /function ConvertTo-AsarFileGlob/);
assert.match(installer, /matches --unpack against the basename on Windows/);
assert.match(installer, /--unpack-dir/);
assert.match(installer, /function Assert-AsarUnpackedEntriesPreserved/);
assert.match(installer, /Preserved \$\(\$patchedUnpackedEntries\.Count\) unpacked ASAR entries/);
assert.match(installer, /src\\update-asar-integrity\.ps1/);
assert.match(installer, /src\\register-rtl-package-identity\.ps1/);
assert.match(installer, /Registering local package identity/);
assert.match(installer, /rtlIdentityPackageFullName/);
assert.match(installer, /rtlAppUserModelId/);
assert.match(installer, /Updating embedded ASAR integrity metadata/);
assert.match(installer, /sourceAsarHeaderSha256/);
assert.match(installer, /patchedAsarHeaderSha256/);
assert.match(installer, /patchedAsarSha256/);
assert.match(launcher, /src\\update-asar-integrity\.ps1/);
assert.match(launcher, /src\\register-rtl-package-identity\.ps1/);
assert.match(launcher, /function Get-RtlShellTarget/);
assert.match(launcher, /shell:AppsFolder\\\$appUserModelId/);

assert.doesNotMatch(rtlPatch, /patch-state\.json|installerScriptPath|Get-AppxPackage/);

console.log("Launcher guard wiring tests passed.");
