#!/usr/bin/env bash
# poll-and-collect.sh — deterministic polling for PR review comments
#
# Polls all three GitHub feedback sources (inline comments, issue-level bot
# comments, top-level reviews) and collects them as structured JSON once
# ready. Enforces minimum wait times and a grace period so slower bots
# (Copilot) aren't missed.
#
# Usage:
#   poll-and-collect.sh <owner/repo> <pr-number> [--since <ISO8601>]
#
# Options:
#   --since   Only count comments/reviews created after this timestamp
#             (used for round 2+ to detect new feedback after a push)
#
# Output: JSON object with three arrays: inline, reviews, bot_comments
#
# Timing:
#   MIN_WAIT=120s   — always wait at least this long before collecting
#   GRACE=60s       — after detecting activity, wait this long for stragglers
#   MAX_WAIT=300s   — hard ceiling on total wait time
#   POLL_INTERVAL=15s

set -euo pipefail

REPO="${1:?Usage: poll-and-collect.sh <owner/repo> <pr-number> [--since <ISO8601>]}"
PR="${2:?Usage: poll-and-collect.sh <owner/repo> <pr-number> [--since <ISO8601>]}"
SINCE=""

shift 2
while [[ $# -gt 0 ]]; do
  case "$1" in
    --since) SINCE="$2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

MIN_WAIT=120
GRACE=60
MAX_WAIT=300
POLL_INTERVAL=15

BOT_PATTERN="claude|coderabbit|copilot"

# --- Counting helpers ---

count_inline() {
  if [[ -n "$SINCE" ]]; then
    gh api "repos/${REPO}/pulls/${PR}/comments" \
      --jq "[.[] | select(.created_at > \"${SINCE}\")] | length" 2>/dev/null || echo 0
  else
    gh api "repos/${REPO}/pulls/${PR}/comments" --jq 'length' 2>/dev/null || echo 0
  fi
}

count_bot_comments() {
  local url="repos/${REPO}/issues/${PR}/comments"
  if [[ -n "$SINCE" ]]; then
    url="${url}?since=${SINCE}"
  fi
  gh api "$url" \
    --jq "[.[] | select(.user.login | test(\"${BOT_PATTERN}\"; \"i\"))] | length" 2>/dev/null || echo 0
}

count_reviews() {
  if [[ -n "$SINCE" ]]; then
    gh api "repos/${REPO}/pulls/${PR}/reviews" \
      --jq "[.[] | select(.submitted_at > \"${SINCE}\" and (.state == \"CHANGES_REQUESTED\" or .state == \"COMMENTED\"))] | length" 2>/dev/null || echo 0
  else
    gh api "repos/${REPO}/pulls/${PR}/reviews" \
      --jq "[.[] | select(.state == \"CHANGES_REQUESTED\" or .state == \"COMMENTED\")] | length" 2>/dev/null || echo 0
  fi
}

# --- Poll loop ---

START=$(date +%s)
GRACE_START=""

while true; do
  ELAPSED=$(( $(date +%s) - START ))

  # Hard ceiling
  if [[ $ELAPSED -ge $MAX_WAIT ]]; then
    echo "timeout: ${ELAPSED}s elapsed, collecting what's available" >&2
    break
  fi

  INLINE=$(count_inline)
  BOT=$(count_bot_comments)
  REVIEWS=$(count_reviews)
  TOTAL=$(( INLINE + BOT + REVIEWS ))

  echo "poll: ${ELAPSED}s elapsed — inline=${INLINE} bot_comments=${BOT} reviews=${REVIEWS}" >&2

  # Nothing at all yet — keep waiting
  if [[ $TOTAL -eq 0 ]]; then
    sleep "$POLL_INTERVAL"
    continue
  fi

  # Something exists — enforce minimum wait
  if [[ $ELAPSED -lt $MIN_WAIT ]]; then
    sleep "$POLL_INTERVAL"
    continue
  fi

  # Both sources present (inline + at least one other)
  HAVE_BOTH=false
  if [[ $INLINE -gt 0 && $(( BOT + REVIEWS )) -gt 0 ]]; then
    HAVE_BOTH=true
  fi

  if [[ "$HAVE_BOTH" == true ]]; then
    # Start grace period on first detection
    if [[ -z "$GRACE_START" ]]; then
      GRACE_START=$(date +%s)
      echo "both sources detected, starting ${GRACE}s grace period for stragglers" >&2
    fi

    GRACE_ELAPSED=$(( $(date +%s) - GRACE_START ))
    if [[ $GRACE_ELAPSED -ge $GRACE ]]; then
      echo "grace period complete, collecting" >&2
      break
    fi

    sleep "$POLL_INTERVAL"
    continue
  fi

  # Only one source — keep polling until max
  sleep "$POLL_INTERVAL"
done

# --- Collect ---

echo "collecting all feedback" >&2

collect_inline() {
  if [[ -n "$SINCE" ]]; then
    gh api "repos/${REPO}/pulls/${PR}/comments" \
      --jq "[.[] | select(.created_at > \"${SINCE}\") | {id, path, line, body, user: .user.login, created_at}]" 2>/dev/null || echo "[]"
  else
    gh api "repos/${REPO}/pulls/${PR}/comments" \
      --jq '[.[] | {id, path, line, body, user: .user.login, created_at}]' 2>/dev/null || echo "[]"
  fi
}

collect_reviews() {
  if [[ -n "$SINCE" ]]; then
    gh api "repos/${REPO}/pulls/${PR}/reviews" \
      --jq "[.[] | select(.submitted_at > \"${SINCE}\" and (.state == \"CHANGES_REQUESTED\" or .state == \"COMMENTED\") and .body != \"\") | {id, body, state, user: .user.login, submitted_at}]" 2>/dev/null || echo "[]"
  else
    gh api "repos/${REPO}/pulls/${PR}/reviews" \
      --jq '[.[] | select((.state == "CHANGES_REQUESTED" or .state == "COMMENTED") and .body != "") | {id, body, state, user: .user.login, submitted_at}]' 2>/dev/null || echo "[]"
  fi
}

collect_bot_comments() {
  local url="repos/${REPO}/issues/${PR}/comments"
  if [[ -n "$SINCE" ]]; then
    url="${url}?since=${SINCE}"
  fi
  gh api "$url" \
    --jq "[.[] | select(.user.login | test(\"${BOT_PATTERN}\"; \"i\")) | {id, body, user: .user.login, created_at}]" 2>/dev/null || echo "[]"
}

# Build combined JSON
INLINE_JSON=$(collect_inline)
REVIEWS_JSON=$(collect_reviews)
BOT_JSON=$(collect_bot_comments)

jq -n \
  --argjson inline "$INLINE_JSON" \
  --argjson reviews "$REVIEWS_JSON" \
  --argjson bot_comments "$BOT_JSON" \
  '{inline: $inline, reviews: $reviews, bot_comments: $bot_comments}'
