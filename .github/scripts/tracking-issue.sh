#!/usr/bin/env bash
# Files a tracker run's outcome through one deduplicated GitHub issue.
# Open issues are matched by exact title under the c2pa-rs-tracking label,
# so repeated runs converge on a single issue per failure mode per branch.
#
# Usage:
#   tracking-issue.sh file <title> <body-file>
#     Open a new issue, or refresh the body of the one already open.
#   tracking-issue.sh close <title> <comment-file>
#     Comment on and close the open issue; a no-op when none is open.
#
# Requires REPO and GH_TOKEN in the environment.
set -euo pipefail

cmd="${1:?usage: tracking-issue.sh <file|close> <title> <path>}"
title="${2:?missing title}"
path="${3:?missing body/comment file}"

# Matched client-side against the label-filtered list rather than through
# `--search`, which goes to the code-search index and is only eventually
# consistent: an issue this script filed moments ago may not be findable yet,
# and two runs of the same branch close together would each open one. The list
# endpoint is strongly consistent, and the label keeps it small.
number="$(gh issue list --repo "$REPO" --label c2pa-rs-tracking --state open \
  --limit 100 --json number,title \
  | jq -r --arg t "$title" 'map(select(.title == $t)) | .[0].number // empty')"

case "$cmd" in
  file)
    if [ -n "$number" ]; then
      gh issue edit "$number" --repo "$REPO" --body-file "$path"
    else
      gh issue create --repo "$REPO" --title "$title" \
        --label c2pa-rs-tracking --body-file "$path"
    fi
    ;;
  close)
    if [ -n "$number" ]; then
      gh issue comment "$number" --repo "$REPO" --body-file "$path"
      gh issue close "$number" --repo "$REPO"
    else
      echo "No open tracking issue to close."
    fi
    ;;
  *)
    echo "unknown command: ${cmd}" >&2
    exit 2
    ;;
esac
