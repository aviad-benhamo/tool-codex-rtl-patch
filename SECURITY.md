# Security Policy

## Supported Versions

This repository is maintained for the current development branch and, when published, the latest released version of the Codex Desktop RTL patch.

The project is Windows-only. Unsupported environments include macOS and other non-Windows platforms.

## Reporting a Vulnerability

Report security issues privately rather than in a public issue when the report includes:

- a secret, token, or credential disclosure
- a local privilege escalation concern
- a path traversal, command injection, or code execution risk
- a flaw that could affect the safety of the local patching process

Preferred reporting path:

1. Open a private GitHub Security Advisory if available for the repository.
2. If a private advisory is not available, open a GitHub issue only after removing exploit details and sensitive data.
3. Include a clear summary of the affected files, the impact, and safe reproduction steps.

Do not include secrets, credentials, private keys, or personal data in any report.

## Security Expectations

- Review local scripts before running the installer or uninstaller.
- Do not execute remote scripts directly into PowerShell.
- Keep backups of the official Codex Desktop installation before patching.
- Revalidate the patch after every Codex Desktop update.

