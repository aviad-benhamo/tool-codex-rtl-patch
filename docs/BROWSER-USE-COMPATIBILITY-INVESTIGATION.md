# Browser Use Compatibility Investigation

## Status

Open. As of Codex Desktop `26.707.3748.0`, there is no safe local fix that
keeps both the local RTL copy and Browser Use stable.

## User Impact

The local `Codex RTL` copy can close when Browser Use opens a page. Use
`Codex (Original)` for Browser Use until a later Codex Desktop release changes
the behavior or a safe replacement architecture is available.

## Working Diagnosis

This is an evidence-based working diagnosis, not a confirmed upstream root
cause.

- The local RTL application exits cleanly while Browser Use attaches a webview.
  The diagnostics monitor recorded exit code `0` for the desktop process tree;
  no Windows Error Reporting event or crash dump was produced.
- The application log reached browser page readiness for `https://example.com/`
  immediately before the local copy exited.
- The local copied runtime reported that it had no package identity.
- Replacing the local copy's patched `app.asar` with the official unmodified
  `app.asar` did not prevent the exit. The renderer RTL script is therefore
  not the cause of this Browser Use failure.

## Completed Experiments

| Experiment | Result | Conclusion |
| --- | --- | --- |
| Preserve the official ASAR `unpacked` metadata during RTL repacking | Preserved all 48 entries; Browser Use still exited | Required installer integrity fix, but not the root cause |
| Run the copied local runtime with the official unmodified `app.asar` | Browser Use still exited | The failure is not caused by the injected RTL asset |
| Run official Codex normally | Browser Use worked | The upstream MSIX runtime is usable without local-copy changes |
| Run official Codex with `--remote-debugging-port` and no RTL injection | Browser Use exited | Remote debugging conflicts with Browser Use in this release |
| Inject RTL at runtime through the Chromium DevTools Protocol | Rejected | It requires remote debugging, which is incompatible with Browser Use |
| Register an MSIX package with external location for the local RTL copy | Registration failed with `0x800B0109` | The package identity proof of concept was not viable on this machine |

## Reverted Experiment State

The package-identity proof of concept was fully rolled back after its failed
registration attempt:

- No external identity package remains registered.
- No local test certificate remains in the current-user personal, trusted
  people, or trusted root stores.
- The local runtime executable was restored from its pre-experiment backup.
- Temporary SDK tools and identity-package artifacts were removed.

The current local RTL installation remains a regular patched copy. Its RTL
asset is present and its ASAR unpack metadata matches the official installation
(48 entries).

## Current Operating Guidance

1. Use `Codex RTL` for normal work that does not need Browser Use.
2. Before using Browser Use, switch to `Codex (Original)`.
3. If the original application crashes without special launch arguments, treat
   that as a separate upstream incident and capture its normal application
   logs before changing the RTL installation.
4. Do not launch Codex with `--remote-debugging-port` while testing Browser
   Use. Do not modify the official installation under `WindowsApps`.

## Revalidation After a Codex Desktop Update

Run this checklist after the official Codex Desktop version changes.

1. Record the installed Codex version:

   ```powershell
   Get-AppxPackage -Name OpenAI.Codex | Select-Object Name, Version, InstallLocation
   ```

2. Rebuild the local RTL copy:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
   ```

3. Start the scoped diagnostics monitor in a separate PowerShell window:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\src\monitor-rtl-diagnostics.ps1
   ```

4. Open `Codex RTL`, create a Browser Use tab, and load a simple public page
   such as `https://example.com/`.
5. Keep the application open for at least one minute, then stop the monitor
   with `Ctrl+C`.
6. If the application exits, preserve the generated diagnostics run folder and
   review its process-stop records and matching desktop application logs.
7. If the application remains stable, repeat with a normal Browser Use task
   before declaring the issue resolved.

## Diagnostics Privacy Boundary

`src/monitor-rtl-diagnostics.ps1` records operational metadata only. It does
not collect prompts, conversation content, browser page content, cookies,
history, network traffic, process command lines, or crash-dump bytes.

