---
argument-hint: <cli-skill=version>...
disable-model-invocation: true
name: refresh-cli-skill
user-invocable: true
description:
  Refresh stale CLI-backed skills in PaulRBerg/agent-skills after installed CLI versions advance; update docs from
  official upstream release docs and set references/version.txt.
---

# Refresh CLI Skill

Refresh one or more `skills/cli-*` entries in `~/projects/agent-skills` after the installed CLI version is newer than
the version recorded in `references/version.txt`.

## Arguments

- Accept arguments as `<cli-skill>=<version>`, for example `cli-gh=2.94.0`.
- Treat each version as an already-normalized semver with no leading `v`.
- Stop if no valid skill/version pairs are provided.

## Workflow

1. Work from `~/projects/agent-skills`.
2. Confirm the worktree is clean before editing. If it is dirty, stop and report the dirty paths.
3. For each requested skill:
   - Confirm `skills/<cli-skill>/SKILL.md` exists.
   - Map `cli-<name>` to binary `<name>` and confirm `<name> --version` still reports the requested version.
   - Read the current skill docs and references that mention versioned features, command flags, or upstream links.
   - Consult official upstream release notes, manuals, changelogs, or CLI docs for the requested version.
   - Update only stale or missing facts in the skill docs. Keep edits terse and preserve local safety rules.
   - Write `skills/<cli-skill>/references/version.txt` with exactly the requested semver and one trailing newline.
4. Do not edit unrelated skills, generated lockfiles, installed copies under `~/.agents`, or global Claude/Codex config.
5. Run `just mdformat-write`, `just mdformat-check`, and `just skill-invocation-check`.
6. Leave the commit to the caller. Do not run `/commit` from inside this skill.

## Version Metadata

`references/version.txt` is the wakeup automation contract. It must contain exactly one normalized semver:

```text
1.2.3
```

No leading `v`, prose, comments, ranges, prerelease labels, or extra lines.
