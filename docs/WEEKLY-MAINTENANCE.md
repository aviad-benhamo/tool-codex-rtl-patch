# Weekly Maintenance Guide

This guide describes the weekly maintenance flow for keeping the patched Codex RTL copy up to date with the official Codex desktop app.

## Goal

Use `Codex RTL` for daily work, but periodically open the official `Codex (Original)` app to allow updates.
After the original app updates, rebuild the RTL copy from the latest official version.
The `Codex RTL` launcher checks the official package version against
`%LOCALAPPDATA%\OpenAI\CodexRtl\patch-state.json` and warns if the RTL copy was
built from an older version.

## Recommended Frequency

Run this check once a week, or whenever Codex announces an update.

## Desktop Shortcuts

There should be two main launchers on the Desktop:

* `Codex RTL` — daily-use patched RTL version.
* `Codex (Original)` — official Codex app used for updates and comparison.

Both shortcuts close any running Codex process before opening the selected
version. Use them when switching between original and RTL variants.

---

## Weekly Update Flow

### 1. Close all Codex processes

Open PowerShell and run:

```powershell
taskkill /IM Codex.exe /F
```

It is safe if this returns an error saying no process was found.

---

### 2. Open the official Codex app

Open the Desktop shortcut:

```text
Codex (Original)
```

Let Codex load normally.

If the app offers an update, install it.

---

### 3. Verify the official Codex version

After updating, run:

```powershell
Get-AppxPackage OpenAI.Codex | Select-Object Name, Version, InstallLocation
```

Confirm that `InstallLocation` points to:

```text
C:\Program Files\WindowsApps\OpenAI.Codex_...
```

Optional: save the version number in a short maintenance note or commit message.

---

### 4. Close Codex again

```powershell
taskkill /IM Codex.exe /F
```

---

### 5. Go to the patch repository

```powershell
cd C:\Workspace\active\tool-codex-rtl-patch
```

---

### 6. Run tests

```powershell
node .\tests\rtl-direction.test.js
```

Expected result:

```text
RTL direction tests passed
```

---

### 7. Run DryRun

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -DryRun
```

Check that the script finds the current official Codex installation and ends with:

```text
Dry run completed. No files were changed.
```

---

### 8. Rebuild the RTL copy

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

This copies the latest official Codex app into:

```text
%LOCALAPPDATA%\OpenAI\CodexRtl\app
```

and injects the RTL patch into the copied app.
It also refreshes `patch-state.json` so the guarded launcher can detect future
official app updates.

The original Codex installation is not modified.

---

### 9. Open Codex RTL

Open:

```text
Codex RTL
```

---

### 10. Verify the running executable

Run:

```powershell
Get-CimInstance Win32_Process -Filter "name='Codex.exe'" |
    Select-Object ProcessId, ExecutablePath
```

For the RTL version, `ExecutablePath` should point to:

```text
C:\Users\<YourUser>\AppData\Local\OpenAI\CodexRtl\app\Codex.exe
```

For the original version, it should point to:

```text
C:\Program Files\WindowsApps\OpenAI.Codex_...\app\Codex.exe
```

---

## Manual Regression Checklist

After rebuilding RTL, verify:

* Hebrew text is readable and aligned correctly.
* English text remains readable.
* Mixed Hebrew/English messages are acceptable.
* Code blocks remain LTR.
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
Explain this path:
C:\Workspace\active\SnapOrd-V2\server\api\order\order.controller.js
```

```text
Explain this code:
function add(a, b) {
  return a + b;
}
```

---

## If Something Breaks

### Option 1: Use Original Codex

Open:

```text
Codex (Original)
```

This bypasses the RTL copy.

### Option 2: Rebuild RTL

```powershell
cd C:\Workspace\active\tool-codex-rtl-patch
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

### Option 3: Uninstall RTL Copy

```powershell
cd C:\Workspace\active\tool-codex-rtl-patch
powershell -NoProfile -ExecutionPolicy Bypass -File .\uninstall.ps1
```

Then continue using `Codex (Original)`.

---

## Maintenance Notes

* Do not install using `irm | iex`.
* Always run from the local reviewed repository.
* The RTL app is a copied and patched version of the official app.
* The official Windows Store app remains the source of truth.
* After every official Codex update, rerun `install.ps1` to refresh the RTL copy.
* Do not run Original and RTL at the same time; use the desktop shortcuts so the launcher closes the previous process first.
