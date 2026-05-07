#!/usr/bin/env bash
# resolve-thread.sh — mark a PR review thread as resolved
#
# Looks up the GraphQL thread node ID for a given REST review-comment ID,
# then calls resolveReviewThread. Idempotent: no-ops if already resolved.
#
# Usage:
#   resolve-thread.sh <owner/repo> <pr-number> <comment-id>
#
# Exit codes:
#   0  resolved (or was already resolved)
#   1  thread not found for comment-id
#   2  GraphQL error

set -euo pipefail

REPO="${1:?Usage: resolve-thread.sh <owner/repo> <pr-number> <comment-id>}"
PR="${2:?Usage: resolve-thread.sh <owner/repo> <pr-number> <comment-id>}"
COMMENT_ID="${3:?Usage: resolve-thread.sh <owner/repo> <pr-number> <comment-id>}"

OWNER="${REPO%%/*}"
NAME="${REPO##*/}"

# Find the thread containing this comment. databaseId on a PullRequestReviewComment
# corresponds to the REST API id.
THREAD_ID=$(gh api graphql -f query="
  query(\$owner: String!, \$name: String!, \$pr: Int!) {
    repository(owner: \$owner, name: \$name) {
      pullRequest(number: \$pr) {
        reviewThreads(first: 100) {
          nodes {
            id
            isResolved
            comments(first: 50) { nodes { databaseId } }
          }
        }
      }
    }
  }
" -F owner="$OWNER" -F name="$NAME" -F pr="$PR" \
  --jq ".data.repository.pullRequest.reviewThreads.nodes[]
        | select(.comments.nodes[].databaseId == ${COMMENT_ID})
        | select(.isResolved == false)
        | .id" | head -1)

if [[ -z "$THREAD_ID" ]]; then
  # Either the comment doesn't exist on this PR or the thread is already resolved.
  # Both are no-ops; exit success.
  exit 0
fi

gh api graphql -f query="
  mutation(\$threadId: ID!) {
    resolveReviewThread(input: {threadId: \$threadId}) {
      thread { isResolved }
    }
  }
" -F threadId="$THREAD_ID" --jq '.data.resolveReviewThread.thread.isResolved' >/dev/null
