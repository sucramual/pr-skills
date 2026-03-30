---
description: Commit, rebase, push, and open a GitHub PR with an auto-generated description
---

Do the following steps in order:

1. **Stage and commit** all current changes. Look at the diff to write a clear, conventional commit message. If there are no uncommitted changes, skip this step.

2. **Rebase onto main** to ensure a clean linear history:
   ```
   git fetch origin
   git rebase origin/main
   ```
   If there are conflicts, stop and report them clearly — do NOT resolve them automatically.

3. **Push** the current branch to the remote. Use `--force-with-lease` if needed after rebase:
   ```
   git push --set-upstream origin HEAD --force-with-lease
   ```

4. **Generate the PR description:**
   - If `./scripts/generate-pr-description.sh` exists, run it and capture its output.
   - Otherwise, generate the description yourself by analyzing `git log main..HEAD` and `git diff main...HEAD`. Use a concise summary of the changes as the PR body.

5. **Route reviewers and assign the PR** using the config in [routing.json](routing.json). Match changed file paths against `reviewers` keys, always include `alwaysReview` entries, and pick assignees based on whether changes match `aiPatterns`.

6. **Create the PR** using the GitHub CLI:
   ```
   gh pr create --title "<concise title from the changes>" --body "<output from step 4, with reviewer adjustments from step 5>" --assignee <assignees from step 5>
   ```
   Target the repo's default branch. If a PR already exists for this branch, let me know instead of failing.

7. **Launch background review.** After showing the PR URL to the user, use the Agent tool with `run_in_background: true` to spawn a general-purpose agent that invokes the `review-pr` skill for this PR. The `/review-pr` skill already handles waiting for bot comments, polling, and multi-round review.

If any step (1–6) fails, stop and report the error clearly. Step 7 runs in the background and does not block.
