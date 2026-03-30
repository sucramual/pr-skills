# pr-skills

Claude Code skills for automating the PR lifecycle — from commit to post-merge follow-up.

Read the full write-up: [How I Stopped Babysitting My PRs](https://sucramual.github.io/writing/skills/)

## Skills

| Skill | What it does |
|-------|-------------|
| **open-pr** | Commit, rebase onto main, push, generate PR description, route reviewers, create PR, and launch review in background |
| **review-pr** | Wait for bot/human comments, classify feedback (valid/stale/won't-fix), fix valid issues, verify locally, push, reply — runs multiple rounds autonomously |
| **post-merge-followup** | Scan merged PR for follow-ups, create Linear tickets, comment on PR, notify reviewers on Slack |

## Install

Clone into a directory of your choice:

```bash
git clone https://github.com/sucramual/pr-skills.git ~/pr-skills
```

Symlink each skill into your Claude Code skills directory:

```bash
ln -s ~/pr-skills/open-pr ~/.claude/skills/open-pr
ln -s ~/pr-skills/review-pr ~/.claude/skills/review-pr
ln -s ~/pr-skills/post-merge-followup ~/.claude/skills/post-merge-followup
```

## Configure

### open-pr

Copy and edit the routing config:

```bash
cp open-pr/routing.example.json open-pr/routing.json
```

Edit `routing.json` with your org's team handles, reviewers, and assignees.

### review-pr

The verify step (step 5) runs `yarn biome check`, `yarn nx affected -t build`, and `yarn nx affected -t test`. Replace these with your project's lint/build/test commands.

### post-merge-followup

Requires `LINEAR_API_KEY` and `SLACK_BOT_TOKEN` environment variables.

Copy and edit the GitHub-to-Slack mapping:

```bash
cp post-merge-followup/github-to-slack.example.json post-merge-followup/github-to-slack.json
```

In `SKILL.md`, replace `<YOUR_LINEAR_USER_ID>` with your Linear user ID (find it via the Linear API or your profile settings).
