#!/usr/bin/env bash
# update-nightly.sh — Compute all hashes and write data/logseq-nightly.json
#
# Required environment variables:
#   LOGSEQ_REV                  - upstream commit SHA
#   LOGSEQ_VERSION              - version string (e.g. 2.0.0-alpha+nightly.20260127)
#   ASSET_URL_X86_64            - x86_64 desktop tarball download URL
#   ASSET_SHA256_X86_64         - SRI hash of the x86_64 desktop tarball
#   ASSET_URL_AARCH64           - aarch64 desktop tarball download URL
#   ASSET_SHA256_AARCH64        - SRI hash of the aarch64 desktop tarball
#   ASSET_URL_AARCH64_DARWIN    - aarch64-darwin desktop tarball download URL
#   ASSET_SHA256_AARCH64_DARWIN - SRI hash of the aarch64-darwin desktop tarball
#   NIGHTLY_TAG                 - release tag (e.g. nightly-20260127)

set -euo pipefail

MANIFEST="data/logseq-nightly.json"

# ── Phase 1: Validate inputs ────────────────────────────────────────
echo "::group::Phase 1: Validate inputs"
: "${LOGSEQ_REV:?must be set}"
: "${LOGSEQ_VERSION:?must be set}"
: "${ASSET_URL_X86_64:?must be set}"
: "${ASSET_SHA256_X86_64:?must be set}"
: "${ASSET_URL_AARCH64:?must be set}"
: "${ASSET_SHA256_AARCH64:?must be set}"
: "${ASSET_URL_AARCH64_DARWIN:?must be set}"
: "${ASSET_SHA256_AARCH64_DARWIN:?must be set}"
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

# ── Phase 3: Resolve CLI version ─────────────────────────────────────
# Upstream removed `deps/cli` (the nbb sub-package) and now builds the CLI as a
# shadow-cljs release target in `src/main/logseq/cli`. There is no standalone
# CLI package.json to read a version from: `scripts/prepare-cli-package.mjs`
# stamps the prepared package with the root project version, which the nightly
# build sets to LOGSEQ_VERSION. Mirror that here instead of fetching a path that
# no longer exists.
echo "::group::Phase 3: Resolve CLI version"
CLI_VERSION="$LOGSEQ_VERSION"
echo "  cliVersion=$CLI_VERSION"
echo "::endgroup::"

# ── Phase 4: Write manifest with placeholder hashes ─────────────────
echo "::group::Phase 4: Write manifest (placeholder pnpm/vendor hashes)"
PLACEHOLDER="sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
jq -n \
  --arg tag "$NIGHTLY_TAG" \
  --arg publishedAt "$PUBLISHED_AT" \
  --arg urlX86_64 "$ASSET_URL_X86_64" \
  --arg sha256X86_64 "$ASSET_SHA256_X86_64" \
  --arg urlAarch64 "$ASSET_URL_AARCH64" \
  --arg sha256Aarch64 "$ASSET_SHA256_AARCH64" \
  --arg urlAarch64Darwin "$ASSET_URL_AARCH64_DARWIN" \
  --arg sha256Aarch64Darwin "$ASSET_SHA256_AARCH64_DARWIN" \
  --arg logseqRev "$LOGSEQ_REV" \
  --arg logseqVersion "$LOGSEQ_VERSION" \
  --arg cliSrcHash "$CLI_SRC_HASH" \
  --arg cliPnpmDepsHash "$PLACEHOLDER" \
  --arg cliCljDepsHash "$PLACEHOLDER" \
  --arg cliVersion "$CLI_VERSION" \
  '{
    tag: $tag,
    publishedAt: $publishedAt,
    assets: {
      "x86_64-linux": { url: $urlX86_64, sha256: $sha256X86_64 },
      "aarch64-linux": { url: $urlAarch64, sha256: $sha256Aarch64 },
      "aarch64-darwin": { url: $urlAarch64Darwin, sha256: $sha256Aarch64Darwin }
    },
    logseqRev: $logseqRev,
    logseqVersion: $logseqVersion,
    cliSrcHash: $cliSrcHash,
    cliPnpmDepsHash: $cliPnpmDepsHash,
    cliCljDepsHash: $cliCljDepsHash,
    cliVersion: $cliVersion
  }' >"$MANIFEST"
echo "  Wrote $MANIFEST with placeholder cliPnpmDepsHash, cliCljDepsHash"
echo "::endgroup::"

# Helper: build a single FOD with a placeholder hash, parse the real
# `got: sha256-...` line from the failure. Targets one FOD attr at a
# time so the parsed hash is unambiguous even if Nix were to schedule
# unrelated builds in parallel (`logseq-cli` transitively pulls in
# both cliPnpmDeps and cliCljDeps; building one passthru attr forces
# Nix to evaluate only that subgraph).
extract_hash_from_build_failure() {
  local field="$1"
  local target="$2"
  set +e
  local output
  output=$(nix build ".#${target}" 2>&1)
  local exit_code=$?
  set -e
  if [ "$exit_code" -eq 0 ]; then
    echo "ERROR: build of $target succeeded with placeholder $field — should not happen" >&2
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
PNPM_HASH=$(extract_hash_from_build_failure cliPnpmDepsHash logseq-cli.cliPnpmDeps)
echo "  cliPnpmDepsHash=$PNPM_HASH"
jq --arg hash "$PNPM_HASH" '.cliPnpmDepsHash = $hash' "$MANIFEST" >"${MANIFEST}.tmp"
mv "${MANIFEST}.tmp" "$MANIFEST"
echo "::endgroup::"

# ── Phase 6: Resolve cliCljDepsHash ─────────────────────────────────
# cliCljDeps (Maven + git-deps for the shadow-cljs release) is independent of
# cliPnpmDeps, so order between the two FODs does not matter.
echo "::group::Phase 6: Resolve cliCljDepsHash"
CLJ_DEPS_HASH=$(extract_hash_from_build_failure cliCljDepsHash logseq-cli.cliCljDeps)
echo "  cliCljDepsHash=$CLJ_DEPS_HASH"
jq --arg hash "$CLJ_DEPS_HASH" '.cliCljDepsHash = $hash' "$MANIFEST" >"${MANIFEST}.tmp"
mv "${MANIFEST}.tmp" "$MANIFEST"
echo "::endgroup::"

# ── Summary ──────────────────────────────────────────────────────────
echo ""
echo "=== Manifest updated ==="
echo "  tag:                        $NIGHTLY_TAG"
echo "  logseqRev:                  $LOGSEQ_REV"
echo "  logseqVersion:              $LOGSEQ_VERSION"
echo "  assetSha256(x64):           $ASSET_SHA256_X86_64"
echo "  assetSha256(arm):           $ASSET_SHA256_AARCH64"
echo "  assetSha256(darwin-arm64):  $ASSET_SHA256_AARCH64_DARWIN"
echo "  cliSrcHash:                 $CLI_SRC_HASH"
echo "  cliPnpmDepsHash:            $PNPM_HASH"
echo "  cliCljDepsHash:             $CLJ_DEPS_HASH"
echo "  cliVersion:                 $CLI_VERSION"
