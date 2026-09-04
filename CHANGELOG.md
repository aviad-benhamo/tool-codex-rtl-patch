# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Fixed

- Updated the embedded Electron ASAR header hash in the copied Windows runtime
  after repacking, preserving integrity validation and preventing immediate
  startup termination in Codex Desktop builds that enforce ASAR integrity.
- Preserved the official ASAR `unpacked` metadata while injecting the RTL
  renderer asset, with an exact post-pack integrity check for native resources.

### Added

- Added a Browser Use compatibility investigation record with the tested
  hypotheses, reverted experiments, current operating guidance, and an
  update-revalidation checklist.
- Added an opt-in, local-only RTL diagnostics monitor that records scoped
  process, version, Windows event, and crash-dump metadata during a bounded
  troubleshooting session without collecting Codex or browser content.
- Added scoped Windows process-stop tracing to the diagnostics monitor so
  unexpected RTL exits can be correlated with exit codes and parent PIDs.

## [0.2.0] - 2026-07-10

### Fixed

- Resolved the current unified Codex Desktop UI runtime as `ChatGPT.exe`, with
  a `Codex.exe` fallback for older builds, so the local RTL copy no longer
  launches the update trampoline.
- Scoped launcher process termination to recognized Codex Desktop app paths so
  unknown Codex processes, including editor extension backends, are preserved.
- Adapted the local RTL install to the unified ChatGPT Desktop runtime that
  hosts ChatGPT, Codex, and Work.

### Added

- Added a separate `ChatGPT` taskbar shortcut that activates an existing scoped
  Codex Desktop window without restarting either supported runtime.
- Added taskbar identity and relaunch metadata so the supported runtime can
  group under the pinned `ChatGPT` shortcut.

## [0.1.0] - 2026-07-09

### Added

- Initial release-readiness documentation set for the Codex Desktop RTL patch.
- Public-facing roadmap and security policy files.

### Documentation

- Documented upstream attribution to `mnigli/codex-desktop-rtl-patch`, license
  continuity, and Windows-specific fork improvements.
- Added README screenshot references for the RTL Codex Desktop behavior.
- Removed stale private wording and machine-specific repository paths from
  public-facing documentation, and clarified the status of upstream macOS
  reference files.
