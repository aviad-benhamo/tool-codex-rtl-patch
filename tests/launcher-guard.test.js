const assert = require("node:assert/strict");
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
assert.match(launcher, /\$statePath = Join-Path \$installRoot 'patch-state\.json'/);
assert.match(launcher, /packageVersion/);
assert.match(launcher, /installerScriptPath/);
assert.match(launcher, /function Confirm-RtlLaunch/);
assert.match(launcher, /Select Yes to rebuild RTL now\./);
assert.match(launcher, /Select No to continue launching the stale RTL copy\./);
assert.match(launcher, /Invoke-RtlRebuild/);
assert.match(launcher, /Stop-CodexProcesses\s*\r?\n\s*Start-Rtl/);
assert.match(launcher, /Stop-CodexProcesses\s*\r?\nStart-Process -FilePath \(Join-Path \$env:WINDIR 'explorer\.exe'\)/);

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
assert.match(installer, /Remove-LegacyShortcuts/);
assert.match(installer, /installerScriptPath = \$ScriptPath/);
assert.match(installer, /repositoryDir = \$ThisDir/);

assert.doesNotMatch(rtlPatch, /patch-state\.json|installerScriptPath|Get-AppxPackage/);

console.log("Launcher guard wiring tests passed.");
