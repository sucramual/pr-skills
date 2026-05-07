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

Use the polling script — do NOT implement polling logic yourself:

```bash
# Round 1 (all comments)
bash scripts/poll-and-collect.sh <owner>/<repo> <pr-number>

# Subsequent rounds (only new comments since last push)
bash scripts/poll-and-collect.sh <owner>/<repo> <pr-number> --since <ISO_PUSH_TIME>
```

The script path is relative to this skill's base directory. The script handles all timing (2 min minimum wait, 15s polling interval, 60s grace period after first activity, 5 min hard ceiling). It outputs a single JSON object:

```json
{
  "inline": [{"id": 123, "path": "src/foo.ts", "line": 42, "body": "...", "user": "Copilot", "created_at": "..."}],
  "reviews": [{"id": 456, "body": "...", "state": "CHANGES_REQUESTED", "user": "claude[bot]", "submitted_at": "..."}],
  "bot_comments": [{"id": 789, "body": "...", "user": "claude[bot]", "created_at": "..."}]
}
```

If all three arrays are empty after the script completes, report "No review feedback received on PR #N after 5 minutes" and stop. On subsequent rounds, if empty, skip to the final summary.

Also collect CI check failures:

```bash
gh pr checks <pr-number>
# For each failed check:
gh run view <run-id> --log-failed
```

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

### 7. Reply to comments and resolve threads

Reply to each **inline** comment classified in step 3:

```bash
# Reply to inline review comments (both bot and human)
gh api repos/<owner>/<repo>/pulls/<pr>/comments \
  -X POST \
  -f body="<disposition>" \
  -F in_reply_to=<comment_id>
```

Reply templates (two-level classification for downstream automation):

**Valid issues:**
- **Fixed**: `✅ Valid — Fixed in <short-sha>.`
- **TODO**: `✅ Valid — TODO: <brief description of follow-up work>.`

**Invalid issues:**
- **Stale**: `❌ Invalid — stale, the referenced code has already changed.`
- **Won't fix**: `❌ Invalid — <brief reason>.`

Use TODO when the issue is real but out of scope for this PR (needs a broader refactor, separate ticket, etc.). Downstream skills can scan for `✅ Valid — TODO` to collect follow-up items.

When numbering items, use `1.`, `2.` — never `#1`, `#2` (GitHub auto-links `#N` to issues).

Skip issue-level summary comments (CodeRabbit/Claude bot summaries) — only reply to inline review comments that reference specific code.

**After posting each reply, resolve the GitHub conversation thread when the disposition is terminal.** Replying alone leaves the thread open in the UI; an open thread is the visual signal "the user still owes a decision". Reserve open threads for items that genuinely need human follow-up.

| Disposition | Action | Why |
|---|---|---|
| **Fixed** | resolve | work is done; commit speaks for itself |
| **Stale** | resolve | nothing to do; reply explains why |
| **Won't fix** | resolve | deliberate decision; reply explains why |
| **TODO** | leave open | user owes a decision (file follow-up ticket? roll into next PR?) — open thread surfaces it |

Resolve via the included script (idempotent — silently no-ops if already resolved):

```bash
bash scripts/resolve-thread.sh <owner>/<repo> <pr-number> <comment-id>
```

The script path is relative to this skill's base directory.

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

Dispositions: **Fixed (round N)**, **TODO**, **Stale**, **Won't fix**, **Unresolved** (include reason).

If there are **Unresolved** items, present them for human decision. If feedback changed the implementation approach, update the PR description.
