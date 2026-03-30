---
description: Collect follow-up work from a merged PR, create Linear tickets, comment on the PR with links, and DM human reviewers on Slack
---

Scan a merged PR for actionable follow-ups, create Linear tickets for confirmed items, post a summary comment on the PR, and notify human reviewers on Slack. Requires `LINEAR_API_KEY` and `SLACK_BOT_TOKEN` env vars.

The argument is a PR number: `/post-merge-followup 2372`

## 1. Fetch PR context

```bash
gh pr view <PR> --json title,body,state,mergedAt,comments,reviews
gh api repos/{owner}/{repo}/pulls/<PR>/comments
```

Gather: PR body, review comments (human + bot), general comments, unresolved threads.

## 2. Identify the PR's Linear ticket

Parse the PR title for a Linear ticket prefix (e.g., `PLA-1020`, `CORP-1180`). If found, fetch it using the `linear-api` skill scripts:

```bash
bash .claude/skills/linear-api/scripts/linear_client.sh get-issue <TICKET>
```

Extract: ticket identifier, title, project name, project ID, team ID.

## 3. Identify follow-up candidates

Analyze all gathered content for actionable follow-ups:

- **Explicit deferrals** — "out of scope", "follow-up", "separate PR", "TODO"
- **Unresolved suggestions** — review comments acknowledged but not implemented
- **Bot recommendations** — CodeRabbit/Claude/Copilot suggestions that were deferred
- **Discussion ideas** — enhancement ideas raised in comment threads

For each candidate, note: title, who raised it, link to comment, and what needs doing.

Only surface genuinely actionable items — skip minor style nits and resolved discussions.

## 4. Present candidates to user

Present as a table:

```
Found N follow-up candidates from PR #<number>:

| # | Title | Raised by | Source |
|---|-------|-----------|--------|
| 1 | Title | @reviewer | [review comment](link) |
| 2 | Title | @author | "out of scope" in PR body |
| 3 | Title | CodeRabbit | [suggestion](link), deferred |
```

Ask user to confirm which to create tickets for. User may adjust titles, descriptions, or skip items.

**Do not create anything without confirmation.**

## 5. Determine project placement for each confirmed follow-up

For each confirmed item:

1. **Check the source ticket's project** — is it the right fit for this follow-up? A follow-up about infrastructure shouldn't land in a domain-specific project just because the source ticket was there.
2. **If not a fit**, list active/planned projects on the team:
   ```bash
   curl -s -X POST https://api.linear.app/graphql \
     -H "Content-Type: application/json" \
     -H "Authorization: $LINEAR_API_KEY" \
     -d '{"query": "query { team(id: \"<TEAM_ID>\") { projects { nodes { id name state description } } } }"}' \
     | jq '.data.team.projects.nodes[] | select(.state == "started" or .state == "planned")'
   ```
   - If a better existing project fits, suggest it
   - If no project fits, suggest creating a new one
3. **Present recommendation** — always confirm project placement before creating

## 6. Create Linear tickets

Unless the user specifies otherwise, assign tickets to the default assignee (configure your Linear user ID below) and set status to Todo (fetch the "Todo" state ID from the team's workflow states).

For each confirmed follow-up:

```bash
curl -s -X POST https://api.linear.app/graphql \
  -H "Content-Type: application/json" \
  -H "Authorization: $LINEAR_API_KEY" \
  -d '{
    "query": "mutation CreateIssue($input: IssueCreateInput!) { issueCreate(input: $input) { success issue { identifier title url } } }",
    "variables": {
      "input": {
        "teamId": "<TEAM_ID>",
        "projectId": "<PROJECT_ID>",
        "assigneeId": "<YOUR_LINEAR_USER_ID>",
        "title": "<TITLE>",
        "description": "<DESCRIPTION>\n\n### Source\n\nFollow-up from PR #<NUMBER>\nRaised by: @<author>\nOriginal ticket: <TICKET>"
      }
    }
  }'
```

## 7. Comment on the PR

```bash
gh pr comment <PR> --body "## Follow-up tickets created

| Ticket | Title | Project |
|--------|-------|---------|
| [PLA-XXXX](url) | Title | Project Name |

Created from post-merge review of this PR."
```

## 8. Notify human reviewers on Slack

For each created ticket that originated from a **human reviewer** (not bots like CodeRabbit, Claude, or Copilot), DM the reviewer on Slack to let them know their feedback was picked up.

### Lookup GitHub -> Slack ID

Load the mapping from [github-to-slack.json](github-to-slack.json):

```json
{
  "github-username": "<SLACK_MEMBER_ID>",
  "another-username": "<SLACK_MEMBER_ID>"
}
```

If a reviewer's GitHub handle isn't in the mapping, skip the notification and log a warning (don't fail the run).

### Send DM via Slack API

For each reviewer to notify, open a DM channel and post a message. Requires `SLACK_BOT_TOKEN` with `chat:write` and `im:write` scopes.

```bash
# Open a DM channel with the user
CHANNEL_ID=$(curl -s -X POST https://slack.com/api/conversations.open \
  -H "Authorization: Bearer $SLACK_BOT_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"users\": \"<SLACK_MEMBER_ID>\"}" \
  | jq -r '.channel.id')

# Send the notification
curl -s -X POST https://slack.com/api/chat.postMessage \
  -H "Authorization: Bearer $SLACK_BOT_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"channel\": \"$CHANNEL_ID\",
    \"text\": \"Your comment on PR #<NUMBER> was picked up as a follow-up: *<TICKET_ID> — <TITLE>*. <TICKET_URL> | <COMMENT_URL>\",
    \"unfurl_links\": false
  }"
```

### Batching

If the same reviewer raised multiple follow-ups, send a **single message** listing all of them rather than one message per ticket:

```
Your comments on PR #2372 were picked up as follow-ups:

- *PLA-1025 — Add retry logic to webhook handler* (<ticket_url> | <comment_url>)
- *PLA-1026 — Document rate limit behavior* (<ticket_url> | <comment_url>)
```
