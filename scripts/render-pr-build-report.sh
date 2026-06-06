#!/usr/bin/env bash
# render-pr-build-report.sh - Render a Markdown PR comment for a pr-build run.
#
# All inputs via environment variables. Requires jq on PATH (available on all
# GitHub Actions runners; install locally with nix run nixpkgs#jq for testing).
#
# Required:
#   SOURCE_REPO  - owner/repo of the PR source (e.g. logseq/logseq)
#   PR_NUMBER    - PR number (e.g. 42)
#   RUN_URL      - URL of the Actions run (for log links)
#   OUTPUT_PATH  - file path to write the rendered report
#
# Optional (graceful degradation when absent or empty):
#   PR_URL            - full PR HTML URL
#   BUILD_RESULT      - GitHub job result string (success/failure/cancelled/skipped)
#   PUBLISH_RESULT    - GitHub job result string for the publish job
#   SEL_X64           - "true"/"false" whether x86_64-linux was selected
#   SEL_ARM           - "true"/"false" whether aarch64-linux was selected
#   SEL_DARWIN        - "true"/"false" whether aarch64-darwin was selected
#   ASSETS_JSON       - compact JSON array from resolve-build-metadata outputs
#   RELEASE_URL       - URL of the GitHub release
#   RELEASE_TAG       - release tag name
#   KEEP_RELEASE      - "true"/"false" whether assets are kept after the run
#   VALIDATE_RAN      - "true"/"false" whether flake validation ran
#   VALIDATE_SKIP_REASON - reason validation was skipped (when VALIDATE_RAN != true)
#   VERSION           - Logseq version string
#   REVISION          - upstream commit SHA (40 hex chars)

set -euo pipefail

: "${SOURCE_REPO:?SOURCE_REPO must be set}"
: "${PR_NUMBER:?PR_NUMBER must be set}"
: "${RUN_URL:?RUN_URL must be set}"
: "${OUTPUT_PATH:?OUTPUT_PATH must be set}"

SEL_X64="${SEL_X64:-false}"
SEL_ARM="${SEL_ARM:-false}"
SEL_DARWIN="${SEL_DARWIN:-false}"
ASSETS_JSON="${ASSETS_JSON:-[]}"
RELEASE_URL="${RELEASE_URL:-}"
RELEASE_TAG="${RELEASE_TAG:-}"
KEEP_RELEASE="${KEEP_RELEASE:-true}"
VALIDATE_RAN="${VALIDATE_RAN:-false}"
VALIDATE_SKIP_REASON="${VALIDATE_SKIP_REASON:-}"
VERSION="${VERSION:-}"
REVISION="${REVISION:-}"
BUILD_RESULT="${BUILD_RESULT:-}"
PUBLISH_RESULT="${PUBLISH_RESULT:-}"

# --- Helpers ---

# Look up a system in ASSETS_JSON; print the matching object or empty string.
lookup_asset() {
  local system="$1"
  if [ "$ASSETS_JSON" = "[]" ] || [ -z "$ASSETS_JSON" ]; then
    echo ""
    return
  fi
  jq -c --arg s "$system" '.[] | select(.system == $s)' <<<"$ASSETS_JSON" 2>/dev/null || echo ""
}

# Render one table row. Arguments: system label, selected ("true"/"false").
render_row() {
  local system="$1" label="$2" sel="$3"
  if [ "$sel" != "true" ]; then
    printf '| %s | not selected | |\n' "$label"
    return
  fi
  local asset
  asset="$(lookup_asset "$system")"
  if [ -n "$asset" ]; then
    local url tarball hash tarball_name
    url="$(jq -r '.url' <<<"$asset")"
    tarball="$(jq -r '.tarball' <<<"$asset")"
    hash="$(jq -r '.sha256' <<<"$asset")"
    # tarball_name is trusted to match the upstream version-string shape
    # (logseq-<os>-<arch>-<version>.tar.gz), so using it as Markdown link text is accepted by design.
    tarball_name="$(basename "$tarball")"
    # shellcheck disable=SC2016
    printf '| %s | built | [%s](%s) `%s` |\n' "$label" "$tarball_name" "$url" "$hash"
  else
    printf '| %s | failed ([logs](%s)) | |\n' "$label" "$RUN_URL"
  fi
}

# --- Header ---

{
  printf '## Logseq test build: %s#%s\n\n' "$SOURCE_REPO" "$PR_NUMBER"

  if [ -n "$REVISION" ]; then
    rev7="${REVISION:0:7}"
    version_str=""
    [ -n "$VERSION" ] && version_str=" (version \`${VERSION}\`)"
    # shellcheck disable=SC2016
    printf 'Built from [`%s`](https://github.com/%s/commit/%s)%s by [pr-build](%s)\n\n' \
      "$rev7" "$SOURCE_REPO" "$REVISION" "$version_str" "$RUN_URL"
  fi

  # --- Per-system table ---

  printf '| System | Result | Download |\n'
  printf '| --- | --- | --- |\n'
  render_row x86_64-linux x86_64-linux "$SEL_X64"
  render_row aarch64-linux aarch64-linux "$SEL_ARM"
  render_row aarch64-darwin aarch64-darwin "$SEL_DARWIN"
  printf '\n'

  # --- Flake validation ---

  if [ "$VALIDATE_RAN" = "true" ]; then
    printf 'Flake validation: ran\n\n'
  else
    reason="${VALIDATE_SKIP_REASON:-unknown reason}"
    printf 'Flake validation: skipped (%s)\n\n' "$reason"
  fi

  # --- Release link ---

  if [ -n "$RELEASE_URL" ]; then
    if [ "$KEEP_RELEASE" = "true" ]; then
      printf 'Release: %s (assets kept for testing)\n\n' "$RELEASE_URL"
    else
      printf 'Release: %s (deleted after this run)\n\n' "$RELEASE_URL"
    fi
  else
    printf 'Release: not published\n\n'
  fi

  # --- Footer ---

  printf '_This is an unsigned, unofficial test build of unreviewed PR code. Install at your own risk._\n'

} >"$OUTPUT_PATH"
