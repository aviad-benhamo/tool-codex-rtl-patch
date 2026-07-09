# Codex RTL Recovery Procedure

This procedure applies to the Windows-only Codex RTL patch.

The Windows installer creates a separate patched copy under LocalAppData. It
does not intentionally modify the official Microsoft Store/MSIX installation
under `WindowsApps`. Recovery normally consists of removing the copied app and
returning to the regular Codex Desktop shortcut.

Run all commands from PowerShell. Save active work before stopping Codex
processes.

## Quick Recovery

Use this path when `Codex RTL` crashes, fails to launch, or behaves incorrectly.

1. Close every regular and patched Codex window.
2. Open PowerShell in the local repository clone:

```powershell
cd <path-to-local-repository>
```

3. Preview the uninstall:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\uninstall.ps1 -DryRun
```

The expected paths are:

```text
%LOCALAPPDATA%\OpenAI\CodexRtl
<Desktop>\Codex RTL.lnk
<Desktop>\Codex (Original).lnk
```

4. Run the uninstaller:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\uninstall.ps1
```

5. Launch the regular Codex Desktop application from the Start menu.

No restoration of `app.asar` is required on Windows because the official ASAR
was not replaced by this installer.

## Verify Removal

Check that the generated copy and shortcut no longer exist:

```powershell
$installRoot = Join-Path $env:LOCALAPPDATA 'OpenAI\CodexRtl'
$desktop = [Environment]::GetFolderPath('Desktop')
$shortcuts = @(
    (Join-Path $desktop 'Codex RTL.lnk'),
    (Join-Path $desktop 'Codex (Original).lnk'),
    (Join-Path $desktop 'Launch Codex RTL.lnk'),
    (Join-Path $desktop 'Launch Codex Original.lnk')
)

Test-Path -LiteralPath $installRoot
$shortcuts | ForEach-Object { Test-Path -LiteralPath $_ }
```

All four results should be `False`.

The Windows uninstaller removes:

```text
%LOCALAPPDATA%\OpenAI\CodexRtl\app\
%LOCALAPPDATA%\OpenAI\CodexRtl\patch-state.json
<Desktop>\Codex RTL.lnk
<Desktop>\Codex (Original).lnk
```

It also removes older duplicate `Launch Codex ...` shortcuts if they are still
present from a previous install.

It does not remove:

- The official Codex Desktop installation.
- The local Git repository.
- npm cache entries created while obtaining `@electron/asar`.
- An abandoned `%TEMP%\codex-rtl-asar-*` folder left by an abrupt process
  termination.

## If Uninstall Fails

The copied app may still be running and locking files.

First inspect active Codex processes:

```powershell
Get-Process Codex -ErrorAction SilentlyContinue |
    Select-Object Id, ProcessName, Path
```

Close all Codex windows normally. If a process remains, save all work and stop
every process named `Codex`:

```powershell
Stop-Process -Name Codex -Force
powershell -NoProfile -ExecutionPolicy Bypass -File .\uninstall.ps1
```

This also closes the official Codex application if it is running.

## Manual Cleanup

Use manual cleanup only if `uninstall.ps1` cannot complete. This block verifies
the resolved paths before deleting anything:

```powershell
$expectedParent = [System.IO.Path]::GetFullPath(
    (Join-Path $env:LOCALAPPDATA 'OpenAI')
).TrimEnd('\')
$installRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $env:LOCALAPPDATA 'OpenAI\CodexRtl')
).TrimEnd('\')

$isExpectedPath = $installRoot.StartsWith(
    $expectedParent + '\',
    [System.StringComparison]::OrdinalIgnoreCase
)

if (-not $isExpectedPath) {
    throw "Unexpected recovery path: $installRoot"
}

if (Test-Path -LiteralPath $installRoot) {
    Remove-Item -LiteralPath $installRoot -Recurse -Force
}

$desktop = [Environment]::GetFolderPath('Desktop')
$shortcuts = @(
    (Join-Path $desktop 'Codex RTL.lnk'),
    (Join-Path $desktop 'Codex (Original).lnk'),
    (Join-Path $desktop 'Launch Codex RTL.lnk'),
    (Join-Path $desktop 'Launch Codex Original.lnk')
)
foreach ($shortcut in $shortcuts) {
    if (Test-Path -LiteralPath $shortcut) {
        Remove-Item -LiteralPath $shortcut -Force
    }
}
```

Do not delete or edit anything under `C:\Program Files\WindowsApps` during
recovery.

### Optional stale temporary-folder cleanup

List candidates first:

```powershell
$tempRoot = [System.IO.Path]::GetTempPath()
Get-ChildItem -LiteralPath $tempRoot -Directory -Filter 'codex-rtl-asar-*' |
    Select-Object FullName, LastWriteTime
```

Only after confirming they are stale folders created by this installer:

```powershell
$tempRoot = [System.IO.Path]::GetTempPath()
Get-ChildItem -LiteralPath $tempRoot -Directory -Filter 'codex-rtl-asar-*' |
    Where-Object LastWriteTime -lt (Get-Date).AddDays(-1) |
    ForEach-Object {
        $resolved = [System.IO.Path]::GetFullPath($_.FullName)
        if ($resolved.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $resolved -Recurse -Force
        }
    }
```

This optional cleanup is not required to restore normal Codex operation.

## Restore Normal Codex Desktop Usage

After uninstalling the patched copy:

1. Open Codex Desktop from the Windows Start menu, not from `Codex RTL`.
2. Confirm the regular app launches.
3. Confirm your account and expected workspace are available.
4. Verify the `Codex RTL` and `Codex (Original)` desktop shortcuts are gone.

The patch does not create a separate Codex account or intentionally replace
Codex user data. The official and patched executables may use the same existing
Codex profile.

## Verify the Official App Was Not Modified

Locate the current official package:

```powershell
$pkg = Get-AppxPackage -Name OpenAI.Codex |
    Sort-Object Version -Descending |
    Select-Object -First 1

if (-not $pkg) {
    throw 'The official OpenAI.Codex package was not found.'
}

$officialApp = Join-Path $pkg.InstallLocation 'app'
$officialAsar = Join-Path $officialApp 'resources\app.asar'

$pkg.Name
$pkg.Version
$pkg.InstallLocation
Test-Path -LiteralPath $officialAsar
```

The package should be `OpenAI.Codex`, its location should be the official
package location rather than `%LOCALAPPDATA%\OpenAI\CodexRtl`, and the final
result should be `True`.

If a SHA-256 baseline was recorded before installation, compare it:

```powershell
$currentHash = (Get-FileHash -Algorithm SHA256 $officialAsar).Hash
$currentHash
$currentHash -eq $beforeHash
```

The comparison should return `True`. This is the strongest local verification
when `$beforeHash` came from the same official package version.

If Codex updated after the baseline was recorded, the official package version
and ASAR hash may legitimately differ. In that case:

1. Confirm the package location is the official MSIX location.
2. Confirm the regular Start menu application works.
3. Record a new baseline for the new package version before patching again.

You can also confirm that the installer state, when present before uninstall,
describes two different paths:

```powershell
$statePath = Join-Path $env:LOCALAPPDATA 'OpenAI\CodexRtl\patch-state.json'
if (Test-Path -LiteralPath $statePath) {
    $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    $state.sourceAppDir
    $state.targetAppDir
}
```

The source should point to the official package and the target should point to
`%LOCALAPPDATA%\OpenAI\CodexRtl\app`.

## If the Patched App Fails to Launch

1. Close every Codex process.
2. Uninstall the patched copy using the Quick Recovery procedure.
3. Verify the generated folder and shortcut were removed.
4. Launch regular Codex Desktop and confirm it works.
5. Check the current official package and prerequisites:

```powershell
Get-AppxPackage -Name OpenAI.Codex
node --version
npx.cmd --version
Test-Path .\src\codex-rtl-patch.js
```

6. Review the previous installer output for:
   - `robocopy` exit codes greater than 7.
   - `asar extract failed` or `asar pack failed`.
   - A missing `webview\index.html`.
   - A missing local patch file. The Windows installer does not download a
     replacement and will fail closed.
7. Do not retry installation until regular Codex works and the cause has been
   reviewed.

## Reapply After a Codex Update

The patched local copy is not updated automatically. The guarded `Codex RTL`
launcher compares the current official package version with
`%LOCALAPPDATA%\OpenAI\CodexRtl\patch-state.json` and warns before opening a
stale RTL copy. After the official Codex Desktop package updates:

1. Launch regular Codex and confirm the update works.
2. Record the new official package version and ASAR hash:

```powershell
$pkg = Get-AppxPackage -Name OpenAI.Codex |
    Sort-Object Version -Descending |
    Select-Object -First 1
$officialAsar = Join-Path $pkg.InstallLocation 'app\resources\app.asar'
$beforeHash = (Get-FileHash -Algorithm SHA256 $officialAsar).Hash

$pkg.Version
$beforeHash
```

3. From the reviewed local clone, run DryRun:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -DryRun
```

4. Confirm all reported source and target paths are expected.
5. Close all Codex windows.
6. Re-run the installer:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

7. Verify the official ASAR still matches the new baseline:

```powershell
$afterHash = (Get-FileHash -Algorithm SHA256 $officialAsar).Hash
$beforeHash -eq $afterHash
```

8. Launch `Codex RTL` and retest Hebrew/Arabic input, English input, mixed text,
   and LTR code blocks.

The installer refreshes `patch-state.json` and the desktop shortcuts so future
launches can detect the next official app update.

Codex UI internals can change after an update. If installation succeeds but the
UI is broken, uninstall the patched copy and continue using regular Codex until
the patch is reviewed for compatibility.
