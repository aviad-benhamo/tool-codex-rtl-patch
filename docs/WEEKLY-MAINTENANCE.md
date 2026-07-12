# Manual Maintenance and Troubleshooting Guide

This guide describes the manual maintenance and troubleshooting flow for the
patched Codex RTL copy.

In normal use, weekly manual rebuilds are not required. The `Codex RTL` launcher
checks the installed official Codex package version against the local RTL install
state and warns when the RTL copy may be stale. When that happens, the launcher
can rebuild the RTL copy automatically.

Use this guide when:

* You want to verify which Codex executable is running.
* The automatic rebuild prompt fails or is not available.
* You want to manually rebuild the RTL copy.
* You want to run local tests before or after a Codex update.
* `Codex RTL` behaves differently from the official Codex app.

## Normal Update Flow

For regular use:

1. Use `Codex RTL` for daily work.
2. Open `Codex (Original)` occasionally to allow the official Codex app to update.
3. After the official app updates, open `Codex RTL`.
4. If the RTL copy was built from an older official version, the launcher displays
   a rebuild prompt.
5. Select **Yes** to rebuild the RTL copy from the current official Codex package.

The original Microsoft Store / MSIX installation remains the source of truth.
The RTL copy is rebuilt from that official installation.

## Desktop Shortcuts

There should be two selected-variant launchers and one taskbar activation
shortcut on the Desktop:

* `Codex RTL` — daily-use patched RTL version.
* `Codex (Original)` — official Codex app used for updates, troubleshooting, and
  comparison.
* `ChatGPT` — taskbar-friendly entry point that activates the existing Original
  or RTL window without closing or restarting either runtime. If neither is
  open, it starts the last selected variant.

Both shortcuts close only recognized Codex Desktop processes before opening the
selected variant. Unknown Codex processes are preserved by default so tools such
as VS Code Codex are not disrupted by Desktop switching.

`ChatGPT` is intentionally separate from those two launchers and never performs
their process-switching behavior.

## Verify the Official Codex Package

Run:

```powershell
Get-AppxPackage OpenAI.Codex | Select-Object Name, Version, InstallLocation
```

The `InstallLocation` should point to the official MSIX package location:

```text
C:\Program Files\WindowsApps\OpenAI.Codex_...
```

## Verify the Running Executable

Run:

```powershell
Get-CimInstance Win32_Process |
    Where-Object { $_.Name -in @('ChatGPT.exe', 'Codex.exe', 'codex.exe') } |
    Select-Object ProcessId, Name, ExecutablePath
```

For current unified builds, the RTL version should run as:

```text
%LOCALAPPDATA%\OpenAI\CodexRtl\app\ChatGPT.exe
```

For the original version, it should run as:

```text
C:\Program Files\WindowsApps\OpenAI.Codex_...\app\ChatGPT.exe
```

Older Codex builds may use `Codex.exe`; the launcher selects it only when
`ChatGPT.exe` is not present. Confirm the full executable path before stopping
any process.

## Run Local Tests

From the local repository clone, run:

```powershell
node .\tests\rtl-direction.test.js
node .\tests\launcher-guard.test.js
node .\tests\diagnostics-monitor.test.js
```

Expected results should indicate that the direction tests and launcher guard
tests passed.

## Temporarily Capture RTL Diagnostics

Use the diagnostic monitor only when you are about to reproduce a suspected RTL
problem or when an unclear problem has started. It is a separate foreground
PowerShell process: it never starts, stops, rebuilds, or modifies Codex.
It runs directly from this repository clone, so adding or using it does not
require rebuilding the installed RTL copy.

Start it in a separate PowerShell window before reproducing the problem:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\src\monitor-rtl-diagnostics.ps1
```

The default monitor duration is two hours. While it is running, use Codex RTL
normally or perform the suspected reproduction, such as opening the in-app
browser. Stop it with `Ctrl+C` once the test is over. To choose a shorter or
longer bounded session, use a duration from 1 to 480 minutes:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\src\monitor-rtl-diagnostics.ps1 -DurationMinutes 30
```

Each run is written locally under:

```text
%LOCALAPPDATA%\OpenAI\CodexRtl\diagnostics\run-YYYYMMDD-HHMMSS
```

The run folder contains the RTL process-state transitions, official and patched
version metadata, matching Windows `Application Error` and `Windows Error
Reporting` events, process-stop exit codes and parent process IDs when Windows
process tracing is available (with process-handle polling as the non-admin
fallback), and metadata for any new Codex/ChatGPT crash dump. It does
not collect prompts, conversations, browser page contents, cookies, history,
network traffic, process command lines, or crash-dump bytes.

If a crash occurs, leave the monitor window open long enough for one polling
interval (ten seconds by default), then stop it. Keep the run folder for review
and do not share it externally before checking the paths and error text it
contains.

## Manual Dry Run

Use this before manually rebuilding:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -DryRun
```

Check that the script finds the official Codex installation and ends with:

```text
Dry run completed. No files were changed.
```

## Manual Rebuild

Use this only when the automatic rebuild prompt is unavailable, fails, or you
want to force a fresh local RTL copy.

Close all Codex Desktop windows normally. If a Desktop process remains, inspect
its executable path and stop only the specific Desktop PID:

```powershell
Get-CimInstance Win32_Process |
    Where-Object { $_.Name -in @('ChatGPT.exe', 'Codex.exe', 'codex.exe') } |
    Select-Object ProcessId, Name, ExecutablePath

$desktopProcessIds = (Read-Host 'Enter inspected Desktop PIDs separated by comma') -split ',' |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ } |
    ForEach-Object { [int]$_ }
$desktopProcessIds | ForEach-Object {
    Stop-Process -Id $_ -Force -ErrorAction SilentlyContinue
}
```

Do not stop Codex processes by name. Only stop processes whose path is under the
official Codex Desktop app directory or `%LOCALAPPDATA%\OpenAI\CodexRtl\app`.

Then run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

This copies the current official Codex app into:

```text
%LOCALAPPDATA%\OpenAI\CodexRtl\app
```

and injects the RTL patch into the copied app.

It also refreshes `patch-state.json` so the guarded launcher can detect future
official app updates.

The original Codex installation is not modified.

## Manual Regression Checklist

After a rebuild, verify:

* Hebrew text is readable and aligned correctly.
* Arabic text is readable and aligned correctly.
* English text remains readable and left-to-right.
* Mixed Hebrew/English messages are readable.
* Mixed Arabic/English messages are readable.
* Code blocks remain left-to-right.
* Inline code remains readable.
* File paths remain readable.
* Message layout is not globally mirrored.
* Buttons and toolbars do not appear reversed.

Recommended test prompts:

```text
שלום hello
```

```text
Hello שלום
```

```text
مرحبا hello
```

```text
Explain this path:
path\to\tool-codex-rtl-patch\src\launch-codex.ps1
```

```text
Explain this code:
function add(a, b) {
  return a + b;
}
```

## If Something Breaks

### Option 1: Use Original Codex

Open:

```text
Codex (Original)
```

This bypasses the RTL copy and launches the official Codex app.

### Option 2: Rebuild RTL Manually

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -DryRun
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

### Option 3: Uninstall the RTL Copy

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\uninstall.ps1 -DryRun
powershell -NoProfile -ExecutionPolicy Bypass -File .\uninstall.ps1
```

Then continue using `Codex (Original)`.

For full recovery steps, see:

```text
docs/RECOVERY.md
```

## Maintenance Notes

* Do not install using `irm | iex`.
* Always run scripts from a reviewed local repository clone.
* The RTL app is a copied and patched version of the official app.
* The official Microsoft Store / MSIX app remains the source of truth.
* Manual rebuilds are optional in normal use because the launcher can detect a
  stale RTL copy and offer to rebuild it.
* Do not run Original and RTL at the same time. Use the desktop shortcuts so the
  launcher closes the previous recognized Desktop process before opening the
  selected variant.
* If Codex UI internals change after an official update, uninstall the RTL copy
  and continue using regular Codex until the patch is reviewed for compatibility.
