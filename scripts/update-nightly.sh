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

# ── Phase 4: Write manifest with placeholder hashes ─────────────────
echo "::group::Phase 4: Write manifest (placeholder pnpm/vendor hashes)"
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
  --arg cliVendorHash "$PLACEHOLDER" \
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
    cliVendorHash: $cliVendorHash,
    cliVersion: $cliVersion
  }' >"$MANIFEST"
echo "  Wrote $MANIFEST with placeholder cliPnpmDepsHash, cliVendorHash"
echo "::endgroup::"

# Helper: build with placeholder, parse `got: sha256-...` from the failure.
extract_hash_from_build_failure() {
  local field="$1"
  local key_attr="$2"
  set +e
  local output
  output=$(nix build ".#${key_attr}" 2>&1)
  local exit_code=$?
  set -e
  if [ "$exit_code" -eq 0 ]; then
    echo "ERROR: build of $key_attr succeeded with placeholder $field — should not happen" >&2
    return 1
  fi
  local hash
  hash=$(echo "$output" | sed -n 's/.*got: *\(sha256-[A-Za-z0-9+/=]\{44\}\).*/\1/p' | head -1)
  if [ -z "$hash" ]; then
    echo "ERROR: could not extract $field from build output" >&2
    echo "$output" >&2
    return 1
  fi
  echo "$hash"
}

# ── Phase 5: Resolve cliPnpmDepsHash ────────────────────────────────
echo "::group::Phase 5: Resolve cliPnpmDepsHash"
PNPM_HASH=$(extract_hash_from_build_failure cliPnpmDepsHash logseq-cli)
echo "  cliPnpmDepsHash=$PNPM_HASH"
jq --arg hash "$PNPM_HASH" '.cliPnpmDepsHash = $hash' "$MANIFEST" >"${MANIFEST}.tmp"
mv "${MANIFEST}.tmp" "$MANIFEST"
echo "::endgroup::"

# ── Phase 6: Resolve cliVendorHash ──────────────────────────────────
# cliVendor depends on cliPnpmDeps, so the pnpm hash above must already be
# correct in the manifest before we trigger the vendor build.
echo "::group::Phase 6: Resolve cliVendorHash"
VENDOR_HASH=$(extract_hash_from_build_failure cliVendorHash logseq-cli)
echo "  cliVendorHash=$VENDOR_HASH"
jq --arg hash "$VENDOR_HASH" '.cliVendorHash = $hash' "$MANIFEST" >"${MANIFEST}.tmp"
mv "${MANIFEST}.tmp" "$MANIFEST"
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
echo "  cliVendorHash:    $VENDOR_HASH"
echo "  cliVersion:       $CLI_VERSION"
