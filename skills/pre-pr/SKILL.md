---
name: pre-pr
description: Run the pre-PR review pipeline on the current branch. It runs the project's build and test checks, runs parallel bug hunters, has verifiers vote on their findings, runs a security pass, classifies risk, and drafts the PR body. Use before opening or updating a pull request.
---

# Pre-PR review pipeline

Run these steps in order. Steps 2, 3 and 4 run in parallel: send all of their Agent calls in a single message.

## 0. Scope

- **Project rules.** Read `REVIEW.md` (also check `.github/REVIEW.md` and `docs/REVIEW.md`) and whichever of `CLAUDE.md`, `AGENTS.md` and `README.md` exist. The steps below refer to them.
- **Base branch.** Use the base the user named. Otherwise use the branch `git symbolic-ref --short refs/remotes/origin/HEAD` points to (without `origin/`), and fall back to `main`, then `master`.
- The range to review is `<base>...HEAD`, plus any uncommitted changes (`git diff HEAD`). If both are empty, stop and tell the user there is nothing to review.
- **Round tracking.** Store the round number and the last reviewed commit in `.git/pre-pr-state`. Write that file with Bash, because it's ignored by git.
  - Round 1 reviews the whole range.
  - From round 2 on, review only `<last-reviewed-sha>..HEAD`.
  - Follow the "Review rounds" section of `REVIEW.md`. If it has none, after round 3 keep only Important findings.

## 1. Verify

Find the project's build, lint and test commands, in this order:
1. A "Before opening a PR" or similar section in `CLAUDE.md` or `AGENTS.md`, including any command that applies only when certain paths changed.
2. Their "Commands" sections.
3. Standard entry points: `package.json` scripts, `Makefile`, `justfile`, `gradlew`, `Cargo.toml`, `pyproject.toml`, `go.mod`.

Run the commands yourself and show their real output. Never say a check passed without showing its output. If a command fails because the environment is missing something (a toolchain, an SDK, a wrong version), tell the user what's missing, using any setup notes in `CLAUDE.md`. Continue the review anyway, and mark the build as **NOT VERIFIED** in the final report. If you find no commands at all, say so and mark the build NOT VERIFIED.

## 2. Bug hunters (in parallel)

Spawn one `bug-hunter` agent per lens, and give each one the range and its lens.

- Use the lenses listed in the "Review lenses" section of `REVIEW.md`.
- If there is no such section, pick the 3 generic lenses that fit the diff best from `logic-and-edge-cases`, `concurrency-and-lifecycle`, `state-and-data` and `contracts-and-parity`.

## 3. Security pass (in parallel with step 2)

Spawn one `security-reviewer` agent with the same range.

## 4. Risk classification (in parallel with step 2)

Spawn one `risk-classifier` agent with the same range.

## 5. Verify the findings

1. Remove duplicate bug-hunter findings, where the same file, line and defect were reported more than once, then renumber what's left.
2. If any findings remain, spawn three `finding-verifier` agents in parallel. Give each of them the range and every finding.
3. Keep a finding only if at least 2 of the 3 verifiers voted CONFIRMED. Use the severity most of them gave.
4. Security findings skip this vote. They are always reported.

## 6. Simplify (optional)

Run this step only if the risk tier is Medium or High and the build passed. Suggest that the user run `/simplify`. Don't run it yourself, because it edits files.

## 7. Report

Print the report in this order:

1. A count line, for example `2 Important, 1 Nit, 0 Pre-existing, 0 Security`. If there is nothing to fix, say exactly `Nothing to fix.`
2. Build status: passed, failed, or NOT VERIFIED, with the commands run.
3. The verified findings ordered Important, then Nit, then Pre-existing. List no more Nits than `REVIEW.md` allows (3 if it sets no limit). Give each finding's `file:line`, the defect, and its scenario.
4. The security findings.
5. The risk tier, the required approvals, whether a person is needed anyway, and the review effort.
6. A draft PR body. Follow `.github/pull_request_template.md` (or `.github/PULL_REQUEST_TEMPLATE.md`, `docs/pull_request_template.md`) if one exists. Otherwise use the sections **What and why**, **Testing**, **Risk** and **How to revert**. Either way:
   - **Testing**: what was actually run, from step 1.
   - **Risk**: the tier and what triggered it.
   - **How to revert**: write it from the diff, and call out anything a revert won't undo, such as migrated or persisted data.

Then update `.git/pre-pr-state` with the new round number and the current `HEAD`.

Every Important finding must be fixed. Every security finding must be fixed or explained as a false positive before the PR is opened. Don't open the PR yourself unless the user asked you to.
