---
description: Address all PR feedback (human reviewers, bots, CI failures) autonomously, then present unresolved items for human decision
---

**Arguments:** `$ARGUMENTS`

Parse the `--rounds N` flag from arguments (default: 2). Examples:
- `/review` → 2 rounds
- `/review --rounds 1` → 1 round (skip bot polling and round 2)

Do the following steps in order. Run autonomously for up to N rounds — no human confirmation needed until the final summary.

**MANDATORY: You MUST execute all N rounds.** Round 2+ polling (wait 2 min, then poll up to 5 min) is NOT optional and MUST NOT be skipped or shortcut. The only way to reduce rounds is `--rounds 1`. Do not rationalize skipping rounds.

## Round loop (run up to N times)

### 1. Identify the current PR

```bash
gh pr view --json number,url,headRepositoryOwner,headRefName
```

Store the PR number, repo owner/name, and branch.

### 2. Wait for and collect feedback

**On round 1:** check if the PR already has review comments or bot comments. If it does, collect them immediately. If not, wait 2 minutes then poll every 15 seconds for up to 5 minutes total. If still zero after 5 minutes, report "No review feedback received on PR #N after 5 minutes" and stop.

**On subsequent rounds:** wait 2 minutes for bots to re-review the push, then poll every 15 seconds for up to 5 minutes total for NEW comments (created after `PUSH_TIME`). If no new comments appear, skip to the final summary.

Polling commands:

```bash
# Round 1 (all comments)
gh api repos/<owner>/<repo>/pulls/<pr>/comments --jq 'length'
gh api "repos/<owner>/<repo>/issues/<pr>/comments" \
  --jq '[.[] | select(.user.login | test("claude|coderabbit|copilot"; "i"))] | length'

# Subsequent rounds (new comments only — filter by PUSH_TIME)
gh api repos/<owner>/<repo>/pulls/<pr>/comments \
  --jq '[.[] | select(.created_at > "<ISO_PUSH_TIME>")] | length'
gh api "repos/<owner>/<repo>/issues/<pr>/comments?since=<ISO_PUSH_TIME>" \
  --jq '[.[] | select(.user.login | test("claude|coderabbit|copilot"; "i"))] | length'
```

Once comments exist, gather from every source before touching code:

```bash
# All inline review comments (human + bot)
gh api repos/<owner>/<repo>/pulls/<pr>/comments \
  --jq '.[] | {id, path, line, body, user: .user.login, created_at}'

# Issue-level bot comments (Claude bot summary, CodeRabbit summary, etc.)
gh api repos/<owner>/<repo>/issues/<pr>/comments \
  --jq '.[] | select(.user.login | test("claude|coderabbit|copilot"; "i")) | {id, body, user: .user.login, created_at}'

# CI check failures
gh pr checks <pr-number>
# For each failed check:
gh run view <run-id> --log-failed
```

On subsequent rounds, only collect comments created after `PUSH_TIME`.

### 3. Stale detection — critical step

For EACH comment, before attempting a fix:

1. Read the file and line range referenced by the comment
2. Check whether the issue described **still exists in the current code**
3. Classify as:
   - **valid** — the issue is real and present in the current code
   - **stale** — the code has already changed and the issue no longer applies
   - **won't-fix** — the comment is subjective, out of scope, or incorrect

Do NOT fix stale issues. Do NOT fix won't-fix issues.

### 4. Fix all valid issues at once

Make all code changes in a single batch. If a fix introduces a new lint/type error, fix it immediately — not in the next round.

### 5. Verify locally

```bash
yarn biome check --write <changed-files>
yarn nx affected -t build
yarn nx affected -t test
```

All three must pass before pushing. If a test or build fails, fix the issue before continuing.

### 6. Commit and push

Record the current timestamp as `PUSH_TIME` (ISO 8601) immediately before pushing.

```bash
git add <all-changed-files>
git commit -m "address PR review feedback"
git push
```

If no files were changed (all comments were stale or won't-fix), skip this step.

### 7. Reply to resolved comments

Reply to each **inline** comment classified in step 3:

```bash
# Bot inline review comments (use API — no review thread)
gh api repos/<owner>/<repo>/pulls/<pr>/comments/<comment_id>/replies \
  -f body="<disposition>"

# Human inline review threads (use gh pr-review extension)
gh pr-review comments reply --thread-id <thread-id> --body "<disposition>" -R <owner/repo> <pr>
```

Reply templates:
- **Fixed**: `Fixed in <short-sha>.`
- **Stale**: `Stale — the referenced code has already changed.`
- **Won't fix**: `Won't fix — <brief reason>.`

When numbering items, use `1.`, `2.` — never `#1`, `#2` (GitHub auto-links `#N` to issues).

Skip issue-level summary comments (CodeRabbit/Claude bot summaries) — only reply to inline review comments that reference specific code.

### 8. Continue or finish

If this is the final round (round N), go to the final summary. Otherwise, loop back to step 2.

---

## Final summary

After completing all rounds (or fewer if no comments appeared), produce a summary table:

```
## Review summary (rounds: completed/max)

| # | File | Line | Source | Disposition | Detail |
|---|------|------|--------|-------------|--------|
| 1 | src/foo.ts | 42 | claude-bot | Fixed (round 1) | Replaced any with specific type |
| 2 | src/bar.ts | 18 | coderabbit | Stale | Code already refactored in earlier commit |
| 3 | src/baz.ts | 7 | @reviewer | Fixed (round 1) | Renamed variable per review |
| 4 | src/qux.ts | — | CI build | Fixed (round 1) | Missing import |
| 5 | src/quux.ts | 31 | copilot | Won't fix | Stylistic preference |
| 6 | src/corge.ts | 15 | claude-bot | Fixed (round 2) | Added error handling |
| 7 | src/grault.ts | 8 | @reviewer | Unresolved | Needs decision on API design |
```

Dispositions: **Fixed (round N)**, **Stale**, **Won't fix**, **Unresolved** (include reason).

If there are **Unresolved** items, present them for human decision. If feedback changed the implementation approach, update the PR description.
