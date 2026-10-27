# review-agents

Four read-only Claude Code subagents for reviewing code changes. They contain nothing project-specific: each one reads the project's own review rules at run time, and falls back to generic defaults when the project doesn't provide them.

| Agent | What it does | Returns |
|---|---|---|
| `bug-hunter` | Hunts correctness bugs in a diff through one assigned **lens**. Run several in parallel with different lenses. | Up to 8 `FINDING` blocks, or `NO FINDINGS` |
| `finding-verifier` | Checks each bug-hunter finding against the code and votes on it. Run several and keep findings that most of them confirm. | One `CONFIRMED` / `REJECTED` block per finding |
| `security-reviewer` | A separate security pass: CI, dependencies, permissions, secrets, input handling, data handling. | `SECURITY` blocks, or `NO SECURITY FINDINGS` |
| `risk-classifier` | Assigns the change a risk tier and the human approvals it needs, based only on the diff. | A fixed five-line summary |

All four use only `Read`, `Grep`, `Glob` and read-only `git` commands. They never build, edit or push.

## Background

These agents are based on [How the Claude Code team does code review](https://claude.dev/blog/solving-code-review-at-anthropic/) by Addy Osmani, Morgan Westlee Lunt and Qing Wang (claude.dev blog, October 2026). The article describes review as a series of layers, not one final check. This repo covers the layers that run before a pull request is opened:

| Article | Here |
|---|---|
| Check the change before the PR: run tests, builds and linters, and review the diff in a fresh context | `/pre-pr` steps 1–2 |
| Several agents hunt for bugs in parallel, and a separate group of verifiers votes on each finding | `bug-hunter` and `finding-verifier`. Splitting the hunters by **lens** is this repo's addition |
| A separate security pass | `security-reviewer` |
| A classifier sets the risk tier from the change itself, not from who wrote it | `risk-classifier` |
| `REVIEW.md`, written by code owners: what failure looks like, a cap on nits, paths to skip | [`templates/REVIEW.md`](templates/REVIEW.md) |
| Important / Nit / Pre-existing severities, and a cap of three review rounds | The default rules in `REVIEW.md` and `/pre-pr` |

The rest of the article's process isn't covered here: required CI, merge queues, feature flags, staged releases and on-call. Projects need their own setup for those. The default risk tiers are also more lenient than the article's: High needs one code-owner approval, not two. To change that, set the tiers in `REVIEW.md`.

The `/pre-pr` skill (`skills/pre-pr/SKILL.md`) runs them as a pipeline before you open a pull request:

1. Works out the base branch and the range to review, and tracks review rounds in `.git/pre-pr-state`.
2. Runs the project's build, lint and test commands, found in `CLAUDE.md` / `AGENTS.md` or standard entry points (`package.json`, `Makefile`, `gradlew`, …), and shows their real output.
3. In parallel: one `bug-hunter` per lens, one `security-reviewer` and one `risk-classifier`.
4. Removes duplicate findings, then has three `finding-verifier`s vote. A finding is kept when at least 2 of 3 confirm it. Security findings skip the vote.
5. Prints a report with a count line, build status, findings, security findings and the risk tier, and drafts a PR body from the project's PR template.

The skill never edits code or opens the PR unless asked.

## Install

```sh
/path/to/review-agents/install.sh /path/to/project
```

This copies the agents into `<project>/.claude/agents/` and the skill into `<project>/.claude/skills/pre-pr/`. Commit them with the project so CI and other contributors get them too. Run the same command again to update the copies after changing this repo.

| Option | Effect |
|---|---|
| `--link` | Symlink to this repo instead of copying, so edits here take effect immediately. Local use only: the links point to absolute paths on your machine, so CI and other contributors see broken links. |
| `--force` | Replace installed files that differ from this repo's versions. Without it the script skips them, lists them, and exits 1, so local edits are never lost silently. |
| `--review-template` | Also copy `templates/REVIEW.md` into the project, unless it already has a `REVIEW.md`, `.github/REVIEW.md` or `docs/REVIEW.md`. |

Switching between copies and links needs no `--force` as long as the content matches.

To install for your user instead, so every project gets them, symlink them into `~/.claude/`:

```sh
mkdir -p ~/.claude/agents ~/.claude/skills
ln -s "$PWD"/agents/*.md ~/.claude/agents/
ln -s "$PWD"/skills/pre-pr ~/.claude/skills/pre-pr
```

Agents and skills in a project's `.claude/` take precedence over user-level ones with the same name.

## Using the agents directly

Each agent expects its prompt to name a **git range** (for example `main...HEAD`) or include the diff. `bug-hunter` also needs a **lens**, and `finding-verifier` needs the numbered findings. To build your own pipeline, for example in a CI review workflow, follow the same steps as `/pre-pr` above.

## Supporting files the project provides

None of these files is required: without them the agents still run with generic defaults. The more of them a project provides, the more the review reflects that project instead of generic advice.

### `REVIEW.md` (the main one)

All four agents look for it at `REVIEW.md`, `.github/REVIEW.md` or `docs/REVIEW.md`, in that order. It is the rulebook for everyone who reviews the project, human or agent. A starting point is in [`templates/REVIEW.md`](templates/REVIEW.md). The agents look for these sections by name:

| Section | Used by | What to put in it | Default if missing |
|---|---|---|---|
| **What failure looks like** | bug-hunter, finding-verifier | The project's worst failure modes, numbered, each naming the invariant, the code it lives in, and what breaking it looks like. Findings that hit one of these are Important. | Generic correctness: wrong behavior, crashes, data loss |
| **Rules for findings** | bug-hunter, finding-verifier | Severity levels and what each means, caps (for example "at most 3 Nits"), and **styles that are deliberate** and must not be flagged. | Important / Nit / Pre-existing |
| **Review lenses** | bug-hunter | One bullet per lens: its name in backticks, then the files and concerns it covers. Add any project-wide hints for following a scenario (guards to check, where input is validated). | `logic-and-edge-cases`, `concurrency-and-lifecycle`, `state-and-data`, `contracts-and-parity` |
| **Security surface** | security-reviewer | What the project exposes and what it doesn't ("no backend, no network calls"), and which files hold CI, dependencies, permissions and data handling. | Checks every category against whatever the diff touches |
| **Paths to skip** | all | Generated, vendored and wrapper files. | Nothing skipped |
| **Review rounds** | `/pre-pr` | How many review rounds a change gets and what changes in later rounds. | After round 3, only Important findings |
| **Risk tiers** | risk-classifier | A table of tiers, which paths or kinds of edit trigger each, and the approvals each requires. List rules that depend on the content of a hunk (for example "renaming a serialized field is High, adding one with a default is Medium"). | Low = docs only, 0 approvals; Medium = ordinary code, 1; High = CI, dependency manifests, auth, secrets, migrations, persisted formats, public APIs, 1 code-owner approval |

When the same review comment comes up twice, add it to `REVIEW.md` so the next review catches it.

### Project context: `CLAUDE.md`, `AGENTS.md` or `README.md`

All four agents read whichever of these exist, to learn what the project is and how it fits together. An architecture overview that names the key files, the invariants between them, and the patterns new code must follow (for example "every async callback must check the cancellation token") gives `bug-hunter` and `finding-verifier` far more to work with than the code alone.

### Used by `/pre-pr`

- **Build and test commands.** Put them in a "Before opening a PR" section of `CLAUDE.md` or `AGENTS.md`, including commands that apply only when certain paths change (for example "if anything under `ios/` changed, also run …") and setup notes for common environment failures. Without that section the skill falls back to a "Commands" section, then to standard entry points.
- **`.github/pull_request_template.md`**, used for the draft PR body. Without one the skill uses What and why / Testing / Risk / How to revert.

### Not read by anything here

- **`.github/CODEOWNERS`** and branch protection, which enforce the approvals that `risk-classifier` reports. The agent only reports them.

## License

[MIT](LICENSE)
