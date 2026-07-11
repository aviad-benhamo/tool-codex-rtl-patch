const assert = require("node:assert/strict");
const childProcess = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");

const repoRoot = path.join(__dirname, "..");
const monitorPath = path.join(repoRoot, "src", "monitor-rtl-diagnostics.ps1");
const monitor = fs.readFileSync(monitorPath, "utf8");
const maintenanceGuide = fs.readFileSync(
  path.join(repoRoot, "docs", "WEEKLY-MAINTENANCE.md"),
  "utf8"
);

assert.match(monitor, /\[int\]\$DurationMinutes = 120/);
assert.match(monitor, /\[int\]\$PollIntervalSeconds = 10/);
assert.match(monitor, /Application Error', 'Windows Error Reporting/);
assert.match(monitor, /Get-WinEvent -FilterHashtable/);
assert.match(monitor, /Get-CimInstance Win32_Process/);
assert.match(monitor, /ChatGPT\.exe', 'Codex\.exe/);
assert.match(monitor, /StartsWith\(\$parentFull \+ '\\'/);
assert.doesNotMatch(monitor, /\$parentFull \+ '\\\\'/);
assert.match(monitor, /\$previousProcessState = '__uninitialized__'/);
assert.match(monitor, /CrashDumps/);
assert.match(monitor, /copied = \$false/);
assert.match(monitor, /Press Ctrl\+C to stop/);
assert.match(monitor, /Properties\.Name -contains 'patchedAsarSha256'/);
assert.match(monitor, /NoMatchingEventsFound/);
assert.match(monitor, /prompts and conversations/);
assert.match(monitor, /browser page contents, cookies, and history/);
assert.match(maintenanceGuide, /monitor-rtl-diagnostics\.ps1/);

const helpResult = childProcess.spawnSync(
  "powershell.exe",
  ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", monitorPath, "-?"],
  { encoding: "utf8" }
);
assert.equal(
  helpResult.status,
  0,
  helpResult.stderr || helpResult.stdout
);

console.log("RTL diagnostics monitor wiring tests passed.");
