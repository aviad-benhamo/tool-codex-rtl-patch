# Deprecated macOS Auto-Patch Files

This private fork currently supports Windows only. The files in this directory
are retained from upstream for reference and are not a supported installation
or update mechanism.

Do not install or run this LaunchAgent for daily use. In particular, this fork
does not recommend granting Full Disk Access to `/bin/bash` or automatically
modifying the Codex application after updates.

For the supported Windows workflow, use the reviewed local clone and follow
the instructions in [`../README.md`](../README.md). After the official
`Codex (Original)` application updates, rerun `install.ps1` locally to rebuild
the separate `Codex RTL` copy.
