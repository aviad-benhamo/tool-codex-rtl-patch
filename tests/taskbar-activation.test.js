const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const repoRoot = path.join(__dirname, "..");
const activator = fs.readFileSync(
  path.join(repoRoot, "src", "activate-chatgpt.ps1"),
  "utf8"
);
const installer = fs.readFileSync(path.join(repoRoot, "install.ps1"), "utf8");

assert.doesNotMatch(activator, /Stop-Process|taskkill\.exe/i);
assert.doesNotMatch(activator, /-File\s+.*launch-codex\.ps1/i);
assert.match(activator, /Get-CimInstance Win32_Process/);
assert.match(activator, /\$runtimeExecutableNames = @\('ChatGPT\.exe', 'Codex\.exe'\)/);
assert.match(activator, /@\(\$AppDirs \| Where-Object \{ Test-UnderPath \$processPath \$_ \}\)\.Count -gt 0/);
assert.match(activator, /EnumWindows/);
assert.match(activator, /GetWindowThreadProcessId/);
assert.match(activator, /IsIconic/);
assert.match(activator, /SetForegroundWindow/);
assert.match(activator, /AttachThreadInput/);
assert.match(activator, /lastSelectedVariant/);
assert.match(activator, /shell:AppsFolder\\\$originalAppUserModelId/);

assert.match(installer, /\$ChatGptShortcutPath = Join-Path \$DesktopPath 'ChatGPT\.lnk'/);
assert.match(installer, /\$TaskbarAppUserModelId = 'com\.openai\.codex'/);
assert.match(installer, /function Set-ShortcutAppUserModelProperties/);
assert.match(installer, /Set\(store, 5, appId\)/);
assert.match(installer, /Set\(store, 2, command\)/);
assert.match(installer, /Set\(store, 4, name\)/);
assert.match(installer, /Set\(store, 3, icon\)/);
assert.match(installer, /Set-ChatGptShortcutTarget \$ChatGptShortcutPath \$taskbarIcon \$AppUserModelId/);
assert.match(installer, /activate-chatgpt\.ps1/);
assert.match(installer, /\[switch\]\$InstallTaskbarShortcutOnly/);
assert.match(installer, /New-ChatGptShortcut \$TargetAppDir \$sourceAppDir/);
assert.match(installer, /function Update-PinnedTaskbarChatGptShortcuts/);
assert.match(installer, /function Get-InstalledRtlAppUserModelId/);
assert.match(installer, /rtlAppUserModelId/);
assert.match(installer, /\$isTaskbarActivator = \$shortcut\.Arguments -and \$shortcut\.Arguments\.IndexOf/);
assert.match(installer, /Updated pinned ChatGPT shortcut/);

console.log("Taskbar activation wiring tests passed.");
