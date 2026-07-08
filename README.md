# Codex Desktop RTL Patch for Windows

## Badges

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

## Project Status

Experimental.

This is an unofficial Windows-only utility for applying a local right-to-left
presentation patch to Codex Desktop. It is maintained for personal production
use and compatibility with current Codex Desktop releases.

This repository is not an OpenAI product.

## Overview

Codex Desktop RTL Patch creates a separate local copy of the installed Codex
Desktop application, injects RTL presentation logic into that copy, and creates
desktop shortcuts for both the patched and original applications.

The patch is intended for Hebrew, Arabic, and mixed-language Codex usage. It
keeps code blocks, inline code, terminals, editor-like surfaces, and developer
tooling left-to-right.

The Windows installer does not intentionally modify the official Microsoft
Store / MSIX installation under `C:\Program Files\WindowsApps`.

## Features

- Hebrew and Arabic direction detection for rendered text.
- Mixed-language handling for right-to-left and left-to-right content.
- Left-to-right preservation for code, terminals, Monaco, CodeMirror, and
  syntax-highlighted content.
- Composer direction updates while typing.
- Separate `Codex RTL` and `Codex (Original)` desktop shortcuts.
- Guarded launcher that warns when the official Codex package has changed.
- Dry-run install and uninstall scripts.
- Recovery documentation for returning to the official Codex application.

## Screenshots / Demo

No screenshots or public demo are currently included.

This is a local Windows desktop patching utility. Validation is performed by
running the local test file and manually checking RTL behavior in the patched
Codex Desktop copy.

## Quick Start

Requirements:

- Windows 10 or Windows 11.
- Codex Desktop installed from the official source.
- Node.js 22 or newer, including npm and `npx`.
- A reviewed local clone of this repository.

Check prerequisites from PowerShell:

```powershell
Get-AppxPackage -Name OpenAI.Codex
node --version
npx.cmd --version
Test-Path .\src\codex-rtl-patch.js
```

Run a dry run first:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -DryRun
```

Close all Codex windows, then install the local RTL copy:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

After installation:

- Use `Codex RTL` for the patched RTL copy.
- Use `Codex (Original)` for Microsoft Store updates, troubleshooting, and
  comparison with the unpatched application.
- Re-run `install.ps1` after Codex Desktop updates.

To remove the patched copy:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\uninstall.ps1 -DryRun
powershell -NoProfile -ExecutionPolicy Bypass -File .\uninstall.ps1
```

## Configuration

No `.env` file is required for this repository.

The installer discovers its required inputs from the local machine and the
repository:

- Official Codex Desktop package: `Get-AppxPackage -Name OpenAI.Codex`
- Patch source: `src/codex-rtl-patch.js`
- Launcher source: `src/launch-codex.ps1`
- Local install root: `%LOCALAPPDATA%\OpenAI\CodexRtl`
- ASAR tool: `npx --yes @electron/asar@4.2.0`

The absence of `.env.example` is intentional because the project has no runtime
environment variables or secret configuration.

## Design Principles

- Keep Codex functionality unchanged; patch RTL presentation only.
- Preserve code editors, terminals, and developer tooling as left-to-right.
- Keep the official Codex Desktop installation available as the recovery path.
- Install into a reversible local copy under `%LOCALAPPDATA%`.
- Fail clearly when a required local file or tool is missing.
- Avoid remote script execution such as piping downloaded content into
  PowerShell.

## Project Structure

```text
.
|-- install.ps1
|-- uninstall.ps1
|-- src/
|   |-- codex-rtl-patch.js
|   `-- launch-codex.ps1
|-- tests/
|   |-- launcher-guard.test.js
|   `-- rtl-direction.test.js
|-- docs/
|   |-- RECOVERY.md
|   `-- WEEKLY-MAINTENANCE.md
|-- CHANGELOG.md
|-- ROADMAP.md
|-- SECURITY.md
|-- LICENSE
`-- README.md
```

Deprecated upstream macOS and autopatch scripts remain in the repository for
reference, but this fork supports Windows only.

## Architecture

The project is script-driven rather than package-driven.

Runtime flow:

1. `install.ps1` locates the official `OpenAI.Codex` package.
2. The installer mirrors the official app into
   `%LOCALAPPDATA%\OpenAI\CodexRtl\app`.
3. The copied `resources\app.asar` is extracted with `@electron/asar`.
4. `src/codex-rtl-patch.js` is copied into the extracted webview assets.
5. `webview/index.html` is patched to load the RTL script.
6. The ASAR is repacked in the local copy.
7. Desktop shortcuts are created for `Codex RTL` and `Codex (Original)`.
8. `src/launch-codex.ps1` stops existing Codex processes before launching the
   selected variant.

The original Codex installation remains the source of truth for updates. The
RTL copy must be rebuilt after official Codex Desktop updates.

## Development

Run the direction test:

```powershell
node .\tests\rtl-direction.test.js
```

Run the launcher guard test:

```powershell
node .\tests\launcher-guard.test.js
```

Run installer validation without changing files:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -DryRun
```

Manual regression checklist:

- Hebrew text is readable and aligned right-to-left.
- Arabic text is readable and aligned right-to-left.
- English text remains left-to-right.
- Mixed Hebrew or Arabic with English remains readable.
- Code blocks and inline code remain left-to-right.
- Terminal output, file paths, toolbars, buttons, and links are not globally
  mirrored.

Additional documentation:

- [Recovery procedure](docs/RECOVERY.md)
- [Weekly maintenance guide](docs/WEEKLY-MAINTENANCE.md)
- [Security policy](SECURITY.md)

## Roadmap

See [ROADMAP.md](ROADMAP.md).

## Changelog

See [CHANGELOG.md](CHANGELOG.md).

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE).
