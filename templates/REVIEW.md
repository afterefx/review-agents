# REVIEW.md

Guidance for every reviewer of this repo, human or agent. When the same review comment comes up twice, add it here.

## What failure looks like in <project>

<One or two sentences on how the software is used, and so which bugs hurt most.>

1. **<Failure name>.** <The invariant, where it lives (`file`, `function`), and what to flag when a change could break it.>
2. **<Failure name>.** <...>

## Rules for findings

- Every finding must cite `file:line` and state a concrete scenario: the inputs or user actions, then the wrong result. If you can't name the scenario, don't post the finding.
- Rank each finding as one of:
  - **Important**: wrong behavior, a crash, data loss, or one of the failures above.
  - **Nit**: style, naming, or a small simplification. Post at most 3 per review.
  - **Pre-existing**: a real bug in code the diff didn't change. Report it, but don't block the change on it.
- <Deliberate styles not to flag, for example "short names are intentional".>
- Start the summary with a count, for example "2 Important, 1 Nit, 0 Pre-existing". If there's nothing to fix, say exactly that and nothing more.

## Review lenses

<Optional hints that apply to every lens: guards to check, where input is validated.>

- `<lens-name>`: <files and concerns this lens covers> (failures 1, 2)
- `<lens-name>`: <...>

## Security surface

<What the project exposes, and what it doesn't: backend, accounts, network calls, user data.>

- **CI and supply chain**: <paths>
- **Dependencies**: <manifests, lockfiles, wrapper scripts>
- **Permissions and capabilities**: <manifests, entitlements, infra config>
- **Data handling**: <where personal data is stored or sent>

## Paths to skip

<Generated, vendored and wrapper files, for example `**/build/**`, `vendor/**`.>

## Review rounds

Run at most 3 full review rounds per change. From round 2 on, review only the diff since the last review. After round 3, post only Important findings.

## Risk tiers

The tier is set by which files changed, not by who wrote the change. If a change touches more than one tier, the highest tier applies.

| Tier | Applies to | Required before merge |
|---|---|---|
| **Low** | Docs and comments only, with no code or config changes | Automated checks and the security review green. No human approval. |
| **Medium** | Ordinary code changes | Automated checks green, plus 1 approval |
| **High** | Anything listed below | Automated checks green, a Deep review, and 1 code-owner approval |

These paths are High risk and always need a person:

- `.github/**`: CI workflows, CODEOWNERS
- <dependency manifests and lockfiles>
- <permissions, auth, secrets, deploy config>
- <persisted data formats, migrations, public API contracts; say which kinds of edit count>
