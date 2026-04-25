#!/usr/bin/env bash
# Render release notes for a nightly built from a cloned Logseq repository.

set -euo pipefail

: "${LOGSEQ_REV:?must be set}"

MANIFEST_PATH="${MANIFEST_PATH:-../data/logseq-nightly.json}"
OUTPUT_PATH="${OUTPUT_PATH:-static/out/release-notes.md}"
UPSTREAM_REPO_URL="${UPSTREAM_REPO_URL:-https://github.com/logseq/logseq}"
FETCH_REMOTE="${FETCH_REMOTE:-origin}"
FETCH_REF="${LOGSEQ_FETCH_REF:-${LOGSEQ_BRANCH:-}}"

if [[ ! $LOGSEQ_REV =~ ^[0-9a-f]{40}$ ]]; then
  echo "LOGSEQ_REV must be a full 40-character lowercase git SHA" >&2
  exit 1
fi

PREVIOUS_REV=$(jq -r '.logseqRev // ""' "$MANIFEST_PATH")

if [ -n "$PREVIOUS_REV" ] && [[ ! $PREVIOUS_REV =~ ^[0-9a-f]{40}$ ]]; then
  echo "Manifest logseqRev must be a full 40-character lowercase git SHA" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUTPUT_PATH")"

commit_available() {
  git cat-file -e "$1^{commit}" 2>/dev/null
}

try_fetch_history() {
  if [ -z "$FETCH_REF" ]; then
    FETCH_REF=$(git branch --show-current || true)
  fi

  if [ -z "$FETCH_REF" ]; then
    return 1
  fi

  # --deepen is cumulative on the same remote, so successive iterations pull back
  # roughly 200, 1200, then 6200 commits of upstream history. A SHA-only fetch is
  # avoided on purpose: it would surface PREVIOUS_REV as a disconnected commit
  # object and let `git rev-list PREVIOUS_REV..LOGSEQ_REV` silently truncate.
  for deepen_by in 200 1000 5000; do
    if git fetch --no-tags --deepen="$deepen_by" "$FETCH_REMOTE" "$FETCH_REF" 2>/dev/null; then
      if commit_available "$PREVIOUS_REV"; then
        return 0
      fi
    else
      echo "Warning: could not deepen $FETCH_REMOTE/$FETCH_REF by $deepen_by commits" >&2
    fi
  done

  return 1
}

current_short="${LOGSEQ_REV:0:7}"
upstream_repo_url="${UPSTREAM_REPO_URL%.git}"

render_notes() {
  printf 'Automated nightly build for commit [%s](%s/commit/%s).\n' \
    "$current_short" \
    "$upstream_repo_url" \
    "$LOGSEQ_REV"

  if [ -z "$PREVIOUS_REV" ]; then
    printf '\nNo previous nightly revision recorded.\n'
    return 0
  fi

  previous_short="${PREVIOUS_REV:0:7}"
  comparison_url="$upstream_repo_url/compare/$PREVIOUS_REV...$LOGSEQ_REV"

  if [ "$PREVIOUS_REV" = "$LOGSEQ_REV" ]; then
    printf '\nNo changes since last build.\n'
    printf '\n[Full comparison](%s)\n' "$comparison_url"
    return 0
  fi

  if ! commit_available "$PREVIOUS_REV"; then
    try_fetch_history || true
  fi

  if ! commit_available "$PREVIOUS_REV"; then
    echo "::warning::Previous nightly revision $previous_short not available in the local clone; release notes will omit commit details." >&2
    printf '\n## Changes since last build\n\n'
    printf 'Previous nightly revision %s was not available in the local clone, so commit details could not be generated.\n' \
      "$previous_short"
    printf '\n[Full comparison](%s)\n' "$comparison_url"
    return 0
  fi

  commit_count=$(git rev-list --count "$PREVIOUS_REV..$LOGSEQ_REV")
  commit_word="commits"
  if [ "$commit_count" = "1" ]; then
    commit_word="commit"
  fi

  printf '\n## Changes since last build (%s %s)\n\n' "$commit_count" "$commit_word"

  if [ "$commit_count" = "0" ]; then
    # Reachable when LOGSEQ_REV is an ancestor of PREVIOUS_REV (e.g. an upstream force-push).
    printf 'No changes since last build.\n'
  else
    git log --format='- %h %s' --no-decorate "$PREVIOUS_REV..$LOGSEQ_REV"
  fi

  printf '\n[Full comparison](%s)\n' "$comparison_url"
}

render_notes >"$OUTPUT_PATH"

echo "Rendered nightly release notes at $OUTPUT_PATH"
