# Codex Desktop RTL Patch for Windows

Private, unofficial RTL patch for Codex Desktop on Windows.

The patch improves Hebrew, Arabic, and mixed right-to-left text while keeping
code blocks, inline code, terminals, and editor-like surfaces left-to-right.

This private fork currently supports Windows only. The macOS scripts remain in
the repository as deprecated upstream files for reference, but they are
unsupported and should not be used for this fork.

## Safety Model

The Windows installer does not modify the Microsoft Store/MSIX installation
under `C:\Program Files\WindowsApps`.

It copies the installed Codex application to:

```text
%LOCALAPPDATA%\OpenAI\CodexRtl\app
```

It then patches only the copied `resources\app.asar` and creates two explicit
desktop shortcuts:

- `Codex RTL.lnk` runs the guarded launcher and then opens the patched copy
  under `%LOCALAPPDATA%`.
- `Codex (Original).lnk` runs the same launcher and then opens the official
  Store app through its AppsFolder AppUserModelID.

Both shortcuts stop existing `Codex.exe` processes before launching the chosen
variant so Electron's single-instance process cannot reopen the variant that
was already running.

Always install from a reviewed local clone. Do not pipe remote scripts into
PowerShell with `irm | iex`.

## Daily Usage

- Use `Codex RTL` as the daily launcher.
- Keep `Codex (Original)` for Microsoft Store updates, troubleshooting, and
  comparison with the unpatched application.
- When `Codex RTL` detects that the official Store app is newer than the
  recorded RTL source version, it warns before launching and offers to rebuild
  from the reviewed local clone recorded during installation.
- When switching between variants, use `Codex RTL` or `Codex (Original)`.
  Both shortcuts stop the already-running Codex process first.
- After `Codex (Original)` updates, confirm it still works, then rerun
  `install.ps1` from the reviewed local clone to rebuild and re-patch the
  separate RTL copy.

There is no supported macOS or automatic patching workflow in this private
fork. Do not run `install.sh`, `uninstall.sh`, `check-macos.sh`, or the scripts
under `autopatch\`; they are retained only as deprecated upstream reference
files.

## What the Patch Does

- Detects Hebrew and Arabic text and applies RTL direction where appropriate.
- Uses `unicode-bidi: plaintext` for mixed Hebrew and English paragraphs.
- Keeps code, terminals, Monaco, CodeMirror, and syntax-highlighted content LTR.
- Changes the composer direction according to the text being typed.
- Reprocesses dynamically rendered Codex UI content.

## Requirements

- Windows 10 or Windows 11.
- Codex Desktop installed from the official source.
- Node.js 22 or newer, including npm and `npx`.
- A local clone of this repository.

Check the prerequisites from PowerShell:

```powershell
Get-AppxPackage -Name OpenAI.Codex
node --version
npx.cmd --version
Test-Path .\src\codex-rtl-patch.js
```

The first command should return the installed Codex package, and the final
command should return `True`.

## Safe Installation

### 1. Open the local clone

```powershell
cd C:\Workspace\active\codex-desktop-rtl-patch
git status --short
```

Review local changes before running the installer. The installer requires the
local `src\codex-rtl-patch.js` file and never downloads a replacement. If the
file is missing, both DryRun and installation fail before copying or patching
Codex.

### 2. Record the original Codex ASAR hash

This baseline lets you confirm later that the official installation was not
modified:

```powershell
$pkg = Get-AppxPackage -Name OpenAI.Codex |
    Sort-Object Version -Descending |
    Select-Object -First 1
$officialAsar = Join-Path $pkg.InstallLocation 'app\resources\app.asar'
$beforeHash = (Get-FileHash -Algorithm SHA256 $officialAsar).Hash
$beforeHash
```

Keep this PowerShell window open until post-install verification so
`$officialAsar` and `$beforeHash` remain available.

### 3. Run DryRun first

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -DryRun
```

Expected behavior:

- Verifies that the local `src\codex-rtl-patch.js` file exists.
- Finds the installed `OpenAI.Codex` package.
- Finds `npx.cmd` or `npx`.
- Prints planned `robocopy`, ASAR extraction, injection, packing, launcher
  script copy, shortcut actions, and cleanup of old duplicate `Launch ...`
  shortcuts if present.
- Ends with `Dry run completed. No files were changed.`

DryRun does not run `robocopy` or `npx`, download files, create the temporary
ASAR directory, patch files, create a shortcut, or launch Codex. It does require
the local patch file so that the same preflight condition is checked before a
real installation.

Stop if the local patch file, package, or `app.asar` is not found, `npx` is
missing, any planned path is unexpected, or the final no-change message is
absent.

### 4. Close Codex

Close every regular and patched Codex window before installation. This avoids
locked files and prevents Electron from reusing an already-running instance
when the patched copy is launched.

### 5. Run the installer

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

The first real run may use `npx` to obtain the pinned
`@electron/asar@4.2.0` package. Review the security notes below before
proceeding on an untrusted network or machine.

A successful installation ends with:

```text
OK  Codex RTL is installed.
Desktop shortcuts: Codex RTL and Codex (Original)
```

## Verify the Installation

### Verify the created artifacts

```powershell
$installRoot = Join-Path $env:LOCALAPPDATA 'OpenAI\CodexRtl'
$desktop = [Environment]::GetFolderPath('Desktop')
$rtlShortcut = Join-Path $desktop 'Codex RTL.lnk'
$originalShortcut = Join-Path $desktop 'Codex (Original).lnk'

Test-Path (Join-Path $installRoot 'app\Codex.exe')
Test-Path (Join-Path $installRoot 'app\resources\app.asar')
Test-Path (Join-Path $installRoot 'patch-state.json')
Test-Path (Join-Path $installRoot 'launch-codex.ps1')
Test-Path $rtlShortcut
Test-Path $originalShortcut
Get-Content (Join-Path $installRoot 'patch-state.json')
```

All six `Test-Path` commands should return `True`. The state file should name
the official package version, the source and target directories, and the local
installer path used by the launcher rebuild action.

Verify both shortcut targets:

```powershell
$shell = New-Object -ComObject WScript.Shell
$rtlLink = $shell.CreateShortcut($rtlShortcut)
$originalLink = $shell.CreateShortcut($originalShortcut)

@(
    [pscustomobject]@{ Shortcut = 'Codex RTL'; Link = $rtlLink }
    [pscustomobject]@{ Shortcut = 'Codex (Original)'; Link = $originalLink }
) | Select-Object Shortcut,
    @{ Name = 'Target'; Expression = { $_.Link.TargetPath } },
    @{ Name = 'Arguments'; Expression = { $_.Link.Arguments } }
```

Both shortcuts should target Windows PowerShell. `Codex RTL` should run:

```text
%LOCALAPPDATA%\OpenAI\CodexRtl\launch-codex.ps1 -Variant Rtl
```

`Codex (Original)` should run:

```text
%LOCALAPPDATA%\OpenAI\CodexRtl\launch-codex.ps1 -Variant Original
```

### Switch between Codex variants

1. Open `Codex RTL` and verify the RTL executable starts.
2. Open `Codex (Original)`.
3. Verify the existing Codex processes terminate and original Codex starts.
4. Repeat in the opposite direction.

Both desktop shortcuts run `taskkill /IM Codex.exe /F`, ignore the error when no
process exists, wait two seconds, and then start the selected variant.

### Verify which Codex version is running

Open one of the desktop shortcuts, then run:

```powershell
Get-CimInstance Win32_Process -Filter "name='Codex.exe'" |
    Select-Object ProcessId, ExecutablePath, CommandLine
```

`Codex RTL` should show an `ExecutablePath` under:

```text
C:\Users\<you>\AppData\Local\OpenAI\CodexRtl\
```

Close it before testing the other shortcut. `Codex (Original)` should show an
`ExecutablePath` under:

```text
C:\Program Files\WindowsApps\OpenAI.Codex_<version>_x64__2p2nqsd0c76g0\app\
```

### Verify the official Codex installation was not modified

In the same PowerShell window used to record the baseline:

```powershell
$afterHash = (Get-FileHash -Algorithm SHA256 $officialAsar).Hash
$beforeHash -eq $afterHash
```

The result should be `True`.

Also confirm that the patched ASAR is in the separate local copy:

```powershell
$patchedAsar = Join-Path $env:LOCALAPPDATA 'OpenAI\CodexRtl\app\resources\app.asar'
$officialAsar
$patchedAsar
Test-Path $officialAsar
Test-Path $patchedAsar
```

Both files should exist at different paths. The official path should be inside
the installed MSIX package; the patched path should be under LocalAppData.

### Verify the RTL behavior

1. Ensure all existing Codex windows are closed.
2. Open the desktop shortcut named `Codex RTL`.
3. Confirm Codex starts normally and can access the expected account/workspace.
4. Type a Hebrew or Arabic sentence in the composer and confirm it aligns RTL.
5. Type an English sentence and confirm it aligns LTR.
6. Type an English-first mixed sentence such as `Hello שלום` and confirm the
   composer remains LTR.
7. Type a Hebrew-first mixed sentence such as `שלום hello` and confirm the
   composer becomes RTL.
8. Open a response containing code and confirm code blocks and inline code
   remain LTR.
9. Confirm message rows, toolbars, buttons, links, badges, and list containers
   remain in their normal LTR layout.

Run the lightweight direction tests from the repository:

```powershell
node .\tests\rtl-direction.test.js
```

Use `Codex RTL` when switching from the original app. The shortcut terminates
existing Codex processes before starting the RTL copy, preventing Electron from
reusing the wrong single-instance process.

## Files and Folders Created

Persistent files:

```text
%LOCALAPPDATA%\OpenAI\CodexRtl\app\
%LOCALAPPDATA%\OpenAI\CodexRtl\launch-codex.ps1
%LOCALAPPDATA%\OpenAI\CodexRtl\patch-state.json
<Desktop>\Codex RTL.lnk
<Desktop>\Codex (Original).lnk
```

Temporary or indirect files:

- `%TEMP%\codex-rtl-asar-<GUID>\` exists while ASAR extraction and packing run.
  The installer removes it on normal completion or handled failure.
- The normal npm cache may retain `@electron/asar` and its dependencies.

Do not store personal files under `%LOCALAPPDATA%\OpenAI\CodexRtl`. Re-running
the installer mirrors the official app with `robocopy /MIR` and may delete
unexpected files from the copied app directory.

## Uninstall

Close all Codex windows, then run from the local clone:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\uninstall.ps1 -DryRun
powershell -NoProfile -ExecutionPolicy Bypass -File .\uninstall.ps1
```

The uninstaller removes:

```text
%LOCALAPPDATA%\OpenAI\CodexRtl\
<Desktop>\Codex RTL.lnk
<Desktop>\Codex (Original).lnk
```

Verify removal:

```powershell
Test-Path "$env:LOCALAPPDATA\OpenAI\CodexRtl"
Test-Path "$([Environment]::GetFolderPath('Desktop'))\Codex RTL.lnk"
Test-Path "$([Environment]::GetFolderPath('Desktop'))\Codex (Original).lnk"
```

All three commands should return `False`. The official Codex installation remains
installed and unchanged.

## Recovery

For the full incident and recovery runbook, see
[`docs/RECOVERY.md`](docs/RECOVERY.md).

If `Codex RTL` fails to start, crashes, or behaves incorrectly:

1. Close all Codex windows.
2. Run the uninstaller from the local clone:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\uninstall.ps1
```

3. Launch the regular Codex Desktop application from the Start menu.
4. Confirm the regular application still works.
5. Review the installer output and the current Codex package version before
   attempting another install.

If the uninstaller cannot remove the copy because a process is still running:

```powershell
Get-Process Codex -ErrorAction SilentlyContinue
Stop-Process -Name Codex -Force
powershell -NoProfile -ExecutionPolicy Bypass -File .\uninstall.ps1
```

`Stop-Process` closes every process named `Codex`, including the official app,
so save active work first.

As a final manual recovery, only after verifying the paths:

```powershell
$installRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $env:LOCALAPPDATA 'OpenAI\CodexRtl')
)
$expectedRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $env:LOCALAPPDATA 'OpenAI')
)

if (
    $installRoot.StartsWith($expectedRoot + '\', [StringComparison]::OrdinalIgnoreCase) -and
    (Test-Path -LiteralPath $installRoot)
) {
    Remove-Item -LiteralPath $installRoot -Recurse -Force
}

$desktop = [Environment]::GetFolderPath('Desktop')
@(
    (Join-Path $desktop 'Codex RTL.lnk'),
    (Join-Path $desktop 'Codex (Original).lnk'),
    (Join-Path $desktop 'Launch Codex RTL.lnk'),
    (Join-Path $desktop 'Launch Codex Original.lnk')
) | Remove-Item -Force -ErrorAction SilentlyContinue
```

Recovery never requires editing or deleting files under `WindowsApps`.

## After Codex Desktop Updates

The patched copy does not update automatically with the official package.
Update the original app through the Microsoft Store, then:

1. Launch `Codex (Original)` and confirm the updated official app works.
2. Open the local repository and review any new local changes.
3. Run DryRun:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -DryRun
```

4. Close all Codex windows.
5. Re-run the installer:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

The installer mirrors the latest official app into the local copy and reapplies
the patch. It also refreshes the two desktop shortcuts. Repeat the artifact,
original-hash, launch-path, and RTL checks above.

Codex UI internals may change between releases. A successful installer run does
not guarantee that the injected patch remains compatible with every new Codex
version.

## Security Notes

- Do not use `irm | iex` or execute installer content directly from a URL.
- Review the local scripts and `src\codex-rtl-patch.js` before installation.
- The installer never downloads the RTL patch. A missing local
  `src\codex-rtl-patch.js` file causes a clear, fail-closed error.
- `npx --yes @electron/asar@4.2.0` may download and execute package code from
  the npm registry. A future hardening step should replace this with a
  lockfile-backed and integrity-verified local dependency workflow.
- The patched Codex copy is not a security sandbox. It may use the same Codex
  account and user-data locations as the official application.

## Project Status

This is an unofficial personal patch, not an OpenAI product. Keep the regular
Codex Desktop installation available as the recovery path and revalidate the
patch after every Codex update.
