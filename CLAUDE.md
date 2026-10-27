# CLAUDE.md

This repo holds Claude Code review agents and the `/pre-pr` skill that runs them. They follow [How the Claude Code team does code review](https://claude.dev/blog/solving-code-review-at-anthropic/). `README.md` is the user-facing documentation. This file covers how to change the repo.

There is no application code. The product is the prompts in `agents/` and `skills/`, plus `install.sh`, which copies or symlinks them into a project's `.claude/` directory. This file is not installed. Other projects never see it.

## Layout

- `agents/*.md`: the four subagents (`bug-hunter`, `finding-verifier`, `security-reviewer`, `risk-classifier`). Each has frontmatter (`name`, `description`, `tools`, `model`), then its instructions.
- `skills/pre-pr/SKILL.md`: the pipeline that runs the agents and reads their output.
- `templates/REVIEW.md`: a starting `REVIEW.md` for projects. `install.sh --review-template` copies it.
- `install.sh`: the installer. It runs on macOS bash 3.2, so it avoids bash 4 features such as associative arrays and `${var,,}`.

## Contracts that span files

The files depend on each other by exact strings. When you change one side, update every other place that uses it in the same change.

- **Output formats.** `SKILL.md` parses each agent's output, so these must stay the same in the agent and in the skill:
  - `FINDING <n>` blocks and `NO FINDINGS` (bug-hunter)
  - `FINDING <n>: CONFIRMED | REJECTED` (finding-verifier)
  - `SECURITY <n>` blocks and `NO SECURITY FINDINGS` (security-reviewer)
  - the five-line `tier` / `approvals` / `triggered-by` / `person-needed-anyway` / `review-effort` summary (risk-classifier)

  The `README.md` agent table describes these too.
- **`REVIEW.md` section names.** Agents find sections by name: "What failure looks like", "Rules for findings", "Review lenses", "Security surface", "Paths to skip", "Review rounds", "Risk tiers". These names must match in the agents, `SKILL.md`, `templates/REVIEW.md` and the section table in `README.md`.
- **`REVIEW.md` lookup order.** Every agent and the skill look in `REVIEW.md`, then `.github/REVIEW.md`, then `docs/REVIEW.md`. `install.sh` checks the same three paths before copying the template.
- **Defaults.** Some defaults appear in more than one place:
  - the generic lenses: `bug-hunter.md`, `SKILL.md` step 2, `README.md`
  - the severities Important / Nit / Pre-existing: `bug-hunter.md`, `finding-verifier.md`, the template, `README.md`
  - the risk tiers: `risk-classifier.md`, the template, `README.md`
  - the 3-round cap and the 3-Nit cap: `SKILL.md`, the template, `README.md`
- **Agent names.** `SKILL.md` spawns agents by their frontmatter `name`, so renaming an agent file means updating the skill and the README.

To find every place that uses a string before you change it, run `grep -rn '<string>' .`.

## Conventions for the prompts

- **Stay generic.** The agents must work in any project. Put project-specific knowledge in the project's `REVIEW.md` or `CLAUDE.md`, and give the agent a generic default for when it's missing. Never hard-code a language, framework or path layout.
- **Read-only agents.** Agents get only `Read, Grep, Glob, Bash`, and their prompts limit Bash to read-only git commands. Only the skill runs builds and tests, and it never edits code or opens the PR unless the user asks.
- **Evidence.** Every finding needs a `file:line` and a concrete scenario. Keep that requirement in every agent that produces or checks findings.
- **Writing style.** Write plain, direct instructions in the second person, as numbered steps where order matters. Use exact output formats in fenced blocks. Match the tone of the files around the one you're editing.
- **Credit the source.** If a change is based on the article, keep the README's "Background" table accurate. If a change departs from the article, say so there.

## Before opening a PR

There is no build or test suite. Run:

```sh
bash -n install.sh
command -v shellcheck >/dev/null && shellcheck install.sh
t=$(mktemp -d) && ./install.sh --review-template "$t" && ./install.sh "$t" && ./install.sh --link "$t" && rm -rf "$t"
```

The smoke test should print `added` lines on the first run, all `ok` on the second, and `updated` when it switches to links. If you changed `install.sh`, also test `--force` against a file that has local edits: without the flag the script should skip the file and exit 1. Make that edit in a *copied* install. In a `--link` install the files are symlinks into this repo, so editing them changes the repo's own files.

If you changed a prompt, run `/pre-pr` (installed at user level) or the agent on its own against a small real diff. Check that the output still matches the formats above.
