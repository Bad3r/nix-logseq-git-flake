#!/usr/bin/env bash
# update-nightly.sh — Compute all hashes and write data/logseq-nightly.json
#
# Required environment variables:
#   LOGSEQ_REV      — upstream commit SHA
#   LOGSEQ_VERSION  — version string (e.g. 2.0.0-alpha+nightly.20260127)
#   ASSET_URL       — tarball download URL
#   ASSET_HASH      — SRI hash of the desktop tarball
#   NIGHTLY_TAG     — release tag (e.g. nightly-20260127)

set -euo pipefail

MANIFEST="data/logseq-nightly.json"

# ── Phase 1: Validate inputs ────────────────────────────────────────
echo "::group::Phase 1: Validate inputs"
: "${LOGSEQ_REV:?must be set}"
: "${LOGSEQ_VERSION:?must be set}"
: "${ASSET_URL:?must be set}"
: "${ASSET_HASH:?must be set}"
: "${NIGHTLY_TAG:?must be set}"
PUBLISHED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
echo "All inputs validated"
echo "  LOGSEQ_REV=$LOGSEQ_REV"
echo "  LOGSEQ_VERSION=$LOGSEQ_VERSION"
echo "  NIGHTLY_TAG=$NIGHTLY_TAG"
echo "  PUBLISHED_AT=$PUBLISHED_AT"
echo "::endgroup::"

# ── Phase 2: Compute CLI source hash ────────────────────────────────
echo "::group::Phase 2: Compute CLI source hash (nix-prefetch-github)"
CLI_SRC_HASH=$(nix shell nixpkgs#nix-prefetch-github nixpkgs#nix-prefetch-git -c \
  nix-prefetch-github logseq logseq --rev "$LOGSEQ_REV" --json | jq -r '.hash')
echo "  cliSrcHash=$CLI_SRC_HASH"
echo "::endgroup::"

# ── Phase 3: Fetch CLI version from upstream ─────────────────────────
echo "::group::Phase 3: Fetch CLI version"
CLI_VERSION=$(curl -fsSL \
  "https://raw.githubusercontent.com/logseq/logseq/${LOGSEQ_REV}/deps/cli/package.json" |
  jq -r '.version')
echo "  cliVersion=$CLI_VERSION"
echo "::endgroup::"

# ── Phase 4: Write manifest with placeholder pnpm hash ──────────────
echo "::group::Phase 4: Write manifest (placeholder pnpm hash)"
PLACEHOLDER="sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
jq -n \
  --arg tag "$NIGHTLY_TAG" \
  --arg publishedAt "$PUBLISHED_AT" \
  --arg assetUrl "$ASSET_URL" \
  --arg assetSha256 "$ASSET_HASH" \
  --arg logseqRev "$LOGSEQ_REV" \
  --arg logseqVersion "$LOGSEQ_VERSION" \
  --arg cliSrcHash "$CLI_SRC_HASH" \
  --arg cliPnpmDepsHash "$PLACEHOLDER" \
  --arg cliVersion "$CLI_VERSION" \
  '{
    tag: $tag,
    publishedAt: $publishedAt,
    assetUrl: $assetUrl,
    assetSha256: $assetSha256,
    logseqRev: $logseqRev,
    logseqVersion: $logseqVersion,
    cliSrcHash: $cliSrcHash,
    cliPnpmDepsHash: $cliPnpmDepsHash,
    cliVersion: $cliVersion
  }' >"$MANIFEST"
echo "  Wrote $MANIFEST with placeholder cliPnpmDepsHash"
echo "::endgroup::"

# ── Phase 5: Double-build to extract pnpm deps hash ─────────────────
echo "::group::Phase 5: Double-build for pnpm deps hash"
set +e
BUILD_OUTPUT=$(nix build .#logseq-cli 2>&1)
BUILD_EXIT=$?
set -e

if [ "$BUILD_EXIT" -eq 0 ]; then
  echo "ERROR: nix build succeeded with placeholder hash — this should not happen" >&2
  exit 1
fi

# ── Phase 6: Extract real hash from error output ─────────────────────
PNPM_HASH=$(echo "$BUILD_OUTPUT" | sed -n 's/.*got: *\(sha256-[A-Za-z0-9+/=]\{44\}\).*/\1/p' | head -1)

if [ -z "$PNPM_HASH" ]; then
  echo "ERROR: Could not extract pnpm deps hash from build output" >&2
  echo "Full build output:" >&2
  echo "$BUILD_OUTPUT" >&2
  exit 1
fi
echo "  cliPnpmDepsHash=$PNPM_HASH"
echo "::endgroup::"

# ── Phase 7: Rewrite manifest with real pnpm hash ────────────────────
echo "::group::Phase 7: Finalize manifest"
jq --arg hash "$PNPM_HASH" '.cliPnpmDepsHash = $hash' "$MANIFEST" >"${MANIFEST}.tmp"
mv "${MANIFEST}.tmp" "$MANIFEST"
echo "  Updated $MANIFEST with real cliPnpmDepsHash"
echo "::endgroup::"

# ── Summary ──────────────────────────────────────────────────────────
echo ""
echo "=== Manifest updated ==="
echo "  tag:              $NIGHTLY_TAG"
echo "  logseqRev:        $LOGSEQ_REV"
echo "  logseqVersion:    $LOGSEQ_VERSION"
echo "  assetSha256:      $ASSET_HASH"
echo "  cliSrcHash:       $CLI_SRC_HASH"
echo "  cliPnpmDepsHash:  $PNPM_HASH"
echo "  cliVersion:       $CLI_VERSION"
