# AGENTS.md

This file defines how AI coding agents should work in this repository.

This repository follows the GitHub Repository Standard (GRS). Use the GRS as the source of truth for repository structure, documentation standards, labels, releases, security expectations, audit workflow, and repository health review.

## Communication Rules

- By default, all assistant-to-Aviad chat in the Codex UI should be in Hebrew.
- Progress updates and explanations in the Codex Desktop chat should be in Hebrew unless Aviad explicitly requests otherwise.
- Use English only for terminal-facing content, including shell commands, command-line prompts, and command output summaries.
- If a terminal, CLI tool, or other tool-facing surface cannot reliably display Hebrew, keep that tool-facing content in English and continue the surrounding chat in Hebrew.
- Code, file names, commit messages, technical prompts, test names, documentation, and technical artifacts must be in English.
- In Plan Mode, questions and explanations for Aviad may be in Hebrew, but the final plan must be in English.
- All GitHub content must always be in English, including Issues, Issue comments, pull requests, review comments, labels, repository metadata, release notes, and final implementation summary comments.

## GRS Compliance

- Follow the GitHub Repository Standard (GRS) for repository-level conventions.
- Source of truth: `aviad-benhamo/github-repository-standard`.
- Main standard file: `GRS.md`.
- Standard labels: `tools/labels/labels-grs.json`.
- Repository-specific labels: `tools/labels/repos/*.labels.json`.
- Do not duplicate or reinvent GRS rules inside this repository unless a documented exception is required.
- Keep documentation, labels, release flow, repository metadata, and AI workflow aligned with GRS.
- If GRS and repository-specific notes conflict, stop and ask for clarification unless the exception is explicitly documented.

## GitHub Workflow

- For GitHub issues, comments, pull requests, labels, and repository metadata, use the connected GitHub connector/plugin first.
- Prefer `mcp__codex_apps__github` as the default path. Do not infer that a resource is missing from `Not Found` errors returned by other GitHub MCP tools, and read back important issue comments after writing them when practical.
- Do not use public GitHub web browsing to access private repository issues or metadata.
- Do not repeatedly try public web access when the connector is available.
- Do not treat public GitHub browsing failures as evidence that a repository, issue, or PR is missing.
- Use `gh` CLI only when explicitly requested by the user or when running approved local tooling such as GRS label synchronization scripts.
- Read the relevant GitHub issue before starting issue work.
- Keep work scoped to the issue or task.
- Add a final implementation summary comment in English to the relevant GitHub Issue when the task is complete.
- Required task-related validation must pass before Codex closes a regular GitHub Issue automatically. Do not close an Issue with incomplete implementation, unmet acceptance criteria, a task-related validation failure, or an unresolved blocker.
- A failure is non-blocking only when it is confirmed to be pre-existing, unrelated to the task, unavailable in the current environment, or explicitly accepted by Aviad; document the exception clearly in the English completion summary. Manual or visual verification that only Aviad can perform may remain pending when agent-side implementation and required automated validation are complete and the remaining verification is documented.
- Codex may close an eligible regular GitHub Issue only after the requested implementation is complete, all closure conditions are met, and the English completion summary is the final Issue comment. Otherwise, leave the Issue open.
- Never close an Epic automatically. When a completed Issue is clearly referenced by an Epic checklist, update its corresponding checklist item; leave the Epic open for Aviad's review and project tracking. Aviad may close the Epic after confirming its required outcome and completion criteria; optional future enhancements should be separate backlog Issues.
- If it is unclear whether an Issue is regular or an Epic, leave it open.
- Creating or updating GitHub issues/comments is allowed when requested or required by the issue workflow.
- Pushing branches, opening PRs, or triggering remote CI should not happen unless explicitly requested.

## Branch and Commit Rules

- Do not push directly to `main`.
- The local `main` branch on this machine is the default source of truth for creating issue branches.
- When starting issue work, create the dedicated issue branch from the current local `main`.
- Do not automatically base issue branches on `origin/main`, GitHub `main`, or a freshly fetched upstream state.
- If local `main` and remote `main` appear to diverge, stop and report the situation before choosing a base.
- Do not run `git pull`, `git reset`, `git rebase`, or other synchronization commands that may change local `main` unless explicitly instructed.
- Work on a dedicated branch for each issue or task.

## Local-First Commit Policy

- Default workflow is local-first.
- Codex may create a local commit without additional approval only when the implementation and acceptance criteria are complete, the work is on a dedicated feature branch other than `main`, required task-related validation passes, no blocker remains, and the commit contains only requested-task changes.
- A confirmed pre-existing or unrelated failure, an unavailable environment check, or a failure explicitly accepted by Aviad may be non-blocking only when clearly documented in the English completion summary and post-commit report. Manual verification that only Aviad can perform may remain pending when agent-side implementation and required automated validation are complete. Never use an exception to hide a task-related failure or commit incomplete work as successfully completed.
- Before creating that commit, verify that it excludes temporary files, generated artifacts, secrets, and unrelated user changes, and use a clear, concise English commit message. Prefer Conventional Commits where appropriate.
- Never commit unfinished work, commit directly to `main`, or amend, squash, or rewrite an existing commit unless explicitly instructed.
- Do not push branches to GitHub unless explicitly instructed by the user.
- After creating a commit, report the branch name, commit hash, commit message, validation or tests performed, and any remaining manual verification or follow-up work.
- If the commit conditions are not satisfied, leave the working tree ready for user review and report the reason.
- PR-based workflow is allowed only when explicitly requested.

## Scope Control

- Keep changes narrowly scoped.
- Do not perform unrelated cleanup.
- Do not introduce broad refactors unless explicitly requested.
- Do not silently change public behavior.
- If a larger problem is discovered, document it or propose a separate issue.

### Workspace Boundary

- Never intentionally read, modify, create, move, or delete files outside the current Git repository unless Aviad explicitly instructs you to do so.
- Keep all searches, file operations, and implementation work scoped to the current repository.
- If completing a task would require accessing files outside the repository, stop and ask for explicit permission first.

## Documentation Rules

- Documentation must be English-only.
- Documentation should be professional, concise, self-contained, and GRS-compliant.
- Do not include private notes, chat history, secrets, credentials, or local machine paths.
- Keep repository documentation usable without relying on previous conversations.

## Changelog and Release Rules

### Work Unit Philosophy

- The GitHub Issue is the primary unit of work.
- Commits are implementation details and should not determine changelog entries or release timing.
- Releases represent completed milestones composed of one or more GitHub Issues.
- Update `CHANGELOG.md` based on meaningful completed work, not on commit count or elapsed time.

### Changelog

* Treat `CHANGELOG.md` as the human-readable release history for the repository.
* For every user-facing change, bug fix, feature, documentation baseline update, repository-standard update, release-preparation task, or meaningful maintenance change, determine whether `CHANGELOG.md` must be updated.
* Add notable completed work under the top-level `[Unreleased]` section.
* Keep `[Unreleased]` as the staging area for the next release.
* Changelog entries should describe completed outcomes rather than commits, branches, or implementation activity.
* Do not move entries from `[Unreleased]` into a numbered version section during ordinary Issue implementation.
* At the completion of each Issue, report:

  * `Release impact: None | Patch | Minor | Major`
  * `Release readiness: Not Ready | Candidate | Ready`
* Treat these values as release-planning signals. Issue and commit counts are not sufficient release triggers and do not require a release after every Issue.

### Release Workflow

* Follow the repository's documented release workflow in `docs/RELEASE-WORKFLOW.md`.
* Releases are coherent, validated milestones composed of one or more completed Issues; apply the candidate criteria, readiness conditions, Semantic Versioning rules, and stop conditions in the Release Workflow.
* Do not create a release from an Issue branch.
* Release preparation must be performed from the approved release source branch, normally `main`.
- When the repository reaches `Release readiness: Candidate` or `Ready`, proactively tell Aviad that release work is pending and state the required Semantic Versioning impact.
- Codex must detect and announce release readiness, then wait for explicit approval after Aviad completes manual verification and merges the approved work into `main`.
- Stop before release execution while Aviad performs manual verification, merges the approved branch into `main`, and explicitly authorizes the release.
- After that approval only, Codex may finalize the changelog, update applicable version references, run release validation, create the release commit, push the approved release source branch, create and push an annotated `vMAJOR.MINOR.PATCH` tag, create the corresponding GitHub Release, and update applicable repository-specific release metadata or approved release artifacts.
* Stop and follow the Release Workflow's failure and recovery rules if owner approval is absent, the release source or version is uncertain, validation fails, unrelated changes exist, a blocker remains, or required access is unavailable.
* Never force-push, rewrite published release history, move an existing release tag, or replace a published version silently.
* If release preparation begins but cannot be completed, report exactly which steps succeeded and which steps remain.
* Repository publication and repository visibility changes are separate from normal version releases and still require explicit approval from Aviad. Codex must never change a repository from Private to Public or Public to Private automatically, must never change visibility as part of a normal version release, and must not treat a tag or GitHub Release in a private repository as authorization to publish it. Package publication, deployment, store publication, and external artifact distribution require separate authorization unless an explicit approved repository workflow authorizes them.

## Label Workflow

- GitHub labels must follow GRS.
- Standard labels come from the GRS baseline.
- Repository-specific `Area:*` labels should come from the repo-specific labels file when available.
- Do not invent new label groups without updating GRS or documenting an exception.

## Security Rules

- Never introduce secrets, credentials, tokens, certificates, or private keys.
- Never commit `.env` files.
- Do not bypass authentication, authorization, validation, or security checks.
- Treat security-sensitive changes as dedicated issue work.
- Review AI-generated security changes carefully before merge.

## Validation Rules

- Inspect relevant local files before changing them.
- Run relevant verification commands after changes.
- If tests or checks are unavailable, state that clearly and provide manual validation steps.
- Do not claim validation was performed unless it actually was.

## AI Behavior Rules

- Prefer consistency over cleverness.
- Follow the existing architecture, naming, and style.
- Ask or document assumptions when requirements are ambiguous.
- Avoid speculative changes.
- Summarize meaningful tradeoffs when proposing plans.
- Keep implementation summaries factual and reviewable.

## Repository-Specific Notes

- Project name:
  - tool-codex-rtl-patch

- Repository type/state:
  - Windows desktop utility for applying an RTL patch to Codex Desktop. Personal production tool, maintained for compatibility with new Codex releases.

- Main architecture docs:
  - README.md
  - CHANGELOG.md
  - docs/ (if present)
  - Source code comments for patch implementation

- Main commands:
  - npm install
  - npm test
  - npm run build (if applicable)
  - npm run lint (if configured)

- Test strategy:
  - Verify correct RTL/LTR detection for Hebrew, Arabic, English, mixed-language text, URLs, numbers, code blocks, and terminal output.
  - Validate that unsupported UI elements remain unaffected.
  - Perform manual testing against the latest supported Codex Desktop release after each update.

- Build or release process:
  - Update compatibility with the latest Codex Desktop release.
  - Run tests and manual validation.
  - Update CHANGELOG.md.
  - Create a Git tag and GitHub Release following the GRS release procedure.

- Deployment notes:
  - Windows-only tool.
  - Applies a local patch to a Codex Desktop installation.
  - Existing installations should be backed up before patching.
  - Reapply the patch after Codex Desktop updates when necessary.

- Project-specific restrictions:
  - Windows is the only supported platform.
  - Do not modify Codex functionality beyond RTL presentation.
  - Preserve code editors, terminals, and developer tooling as LTR.
  - Never include proprietary Codex binaries or copyrighted application files in the repository.
  - Keep the project focused on the patch and related tooling only.
