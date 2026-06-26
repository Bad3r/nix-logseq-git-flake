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
# Upstream rewrote the CLI as an OCaml/Melange project under `cli/` (no
# standalone JS package.json to read a version from). `scripts/prepare-cli-package.mjs`
# stamps the prepared package with CLI_PACKAGE_VERSION, which the nightly build
# sets to LOGSEQ_VERSION. Mirror that here.
echo "::group::Phase 3: Resolve CLI version"
CLI_VERSION="$LOGSEQ_VERSION"
echo "  cliVersion=$CLI_VERSION"
echo "::endgroup::"

# ── Phase 3b: Resolve opam pin-depends branch refs ──────────────────
# Upstream cli/logseq-cli.opam (logseq/logseq 3684727952e6) pins some deps
# (melange-edn, humanize, ...) at the mutable `#main` branch. opam-nix refuses a
# git pin without an explicit 40-char sha1 in pure evaluation mode, so opam-deps.nix
# rewrites each branch ref to a commit before resolving. Resolve those branches to
# their current HEAD here so the pin advances every nightly with LOGSEQ_REV instead
# of freezing at a hardcoded commit. Entries already pinned to a sha1 are left alone,
# so this self-clears once upstream restores explicit commits.
#
# Resolve a branch/tag fragment to a commit sha1 on $remote. awk matches $2
# exactly because `git ls-remote <pattern>` tail-matches, so a bare `main` also
# returns refs/heads/feature/main and a positional NR==1 pick could grab the
# wrong ref. Prefer a branch head, then a peeled annotated tag
# (refs/tags/<f>^{} is the commit the tag points at; opam-nix needs a commit,
# not the tag object), then a lightweight tag or an already-qualified ref.
resolve_ref_sha() {
  local remote="$1" frag="$2"
  git ls-remote "$remote" \
    "refs/heads/$frag" "refs/tags/$frag^{}" "refs/tags/$frag" "$frag" |
    awk -v f="$frag" '
      $2 == "refs/heads/" f      { head = $1 }
      $2 == "refs/tags/" f "^{}" { peeled = $1 }
      $2 == "refs/tags/" f       { tag = $1 }
      $2 == f                    { bare = $1 }
      END {
        if (head != "")        print head
        else if (peeled != "") print peeled
        else if (tag != "")    print tag
        else if (bare != "")   print bare
      }'
}
echo "::group::Phase 3b: Resolve opam pin-depends branch refs"
OPAM_RAW_URL="https://raw.githubusercontent.com/logseq/logseq/${LOGSEQ_REV}/cli/logseq-cli.opam"
OPAM_TMP="$(mktemp)"
trap 'rm -f "$OPAM_TMP"' EXIT
curl -fsSL "$OPAM_RAW_URL" -o "$OPAM_TMP"
CLI_OPAM_PIN_OVERRIDES="[]"
# pin-depends URLs are the only git+<proto>://...#<frag> tokens; dev-repo carries no
# fragment and is excluded. `|| true`: no git pins is a valid opam file, not an error.
mapfile -t PIN_URLS < <(grep -oE 'git\+[a-z]+://[^"#]+#[^"]+' "$OPAM_TMP" | sort -u || true)
for url in "${PIN_URLS[@]}"; do
  frag="${url##*#}"
  if [[ $frag =~ ^[0-9a-f]{40}$ ]]; then
    continue
  fi
  base="${url%#*}"
  remote="${base#git+}"
  sha="$(resolve_ref_sha "$remote" "$frag")"
  if [[ ! $sha =~ ^[0-9a-f]{40}$ ]]; then
    echo "ERROR: could not resolve ${remote} ref ${frag} to a commit sha1" >&2
    exit 1
  fi
  CLI_OPAM_PIN_OVERRIDES="$(jq -c --arg from "$url" --arg to "${base}#${sha}" \
    '. + [{ from: $from, to: $to }]' <<<"$CLI_OPAM_PIN_OVERRIDES")"
  echo "  ${url} -> ${base}#${sha}"
done
echo "  cliOpamPinOverrides=$CLI_OPAM_PIN_OVERRIDES"
echo "::endgroup::"

# ── Phase 3c: Preserve toolchain + regenerate patches[] ─────────────
# The manifest owns the CI toolchain versions and the patch declaration list.
# Preserve the committed toolchain block verbatim (a maintainer edits it on a
# major bump, not this script) and regenerate patches[] from the patches/
# directory so .file always matches what is on disk, carrying the hand-set cli
# flag forward (default false for a newly added patch).
echo "::group::Phase 3c: Preserve toolchain + regenerate patches[]"
OLD_TOOLCHAIN="$(jq -c '.toolchain' "$MANIFEST")"
if [ "$OLD_TOOLCHAIN" = "null" ] || [ -z "$OLD_TOOLCHAIN" ]; then
  echo "ERROR: $MANIFEST has no .toolchain block to preserve" >&2
  exit 1
fi
for key in node pnpm java clojure; do
  value="$(jq -r --arg k "$key" '.toolchain[$k] // ""' "$MANIFEST")"
  if [ -z "$value" ]; then
    echo "ERROR: $MANIFEST .toolchain.${key} is missing or empty" >&2
    exit 1
  fi
done
# Enumerate patches/logseq-*.patch by basename, merging the prior cli flag by
# filename (// false for a newly added file). jq -cs slurps the per-file objects
# into one array; OLD_PATCHES is read once for the flag lookup.
OLD_PATCHES="$(jq -c '.patches // []' "$MANIFEST")"
PATCHES_JSON="$(
  for patch in patches/logseq-*.patch; do
    [ -e "$patch" ] || continue
    jq -cn --arg file "$(basename "$patch")" --argjson old "$OLD_PATCHES" \
      '{ file: $file, cli: (($old[] | select(.file == $file) | .cli) // false) }'
  done | jq -cs '.'
)"
echo "  toolchain=$OLD_TOOLCHAIN"
echo "  patches=$PATCHES_JSON"
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
  --argjson cliOpamPinOverrides "$CLI_OPAM_PIN_OVERRIDES" \
  --arg cliPnpmDepsHash "$PLACEHOLDER" \
  --arg cliBundlePnpmDepsHash "$PLACEHOLDER" \
  --arg cliCljDepsHash "$PLACEHOLDER" \
  --arg cliVersion "$CLI_VERSION" \
  --argjson toolchain "$OLD_TOOLCHAIN" \
  --argjson patches "$PATCHES_JSON" \
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
    cliOpamPinOverrides: $cliOpamPinOverrides,
    cliPnpmDepsHash: $cliPnpmDepsHash,
    cliBundlePnpmDepsHash: $cliBundlePnpmDepsHash,
    cliCljDepsHash: $cliCljDepsHash,
    cliVersion: $cliVersion,
    toolchain: $toolchain,
    patches: $patches
  }' >"$MANIFEST"
echo "  Wrote $MANIFEST with placeholder cliPnpmDepsHash, cliBundlePnpmDepsHash, cliCljDepsHash"
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

# ── Phase 6: Resolve cliBundlePnpmDepsHash ──────────────────────────
# cli/pnpm-lock.yaml (vite + transit-js) is a separate workspace from the root
# lock; the OCaml CLI's `dune build @bundle` runs cli/node_modules/.bin/vite.
echo "::group::Phase 6: Resolve cliBundlePnpmDepsHash"
BUNDLE_PNPM_HASH=$(extract_hash_from_build_failure cliBundlePnpmDepsHash logseq-cli.cliBundlePnpmDeps)
echo "  cliBundlePnpmDepsHash=$BUNDLE_PNPM_HASH"
jq --arg hash "$BUNDLE_PNPM_HASH" '.cliBundlePnpmDepsHash = $hash' "$MANIFEST" >"${MANIFEST}.tmp"
mv "${MANIFEST}.tmp" "$MANIFEST"
echo "::endgroup::"

# ── Phase 7: Resolve cliCljDepsHash ─────────────────────────────────
# cliCljDeps (Maven + git-deps for the db-worker shadow-cljs release) is
# independent of the pnpm FODs, so order between them does not matter.
echo "::group::Phase 7: Resolve cliCljDepsHash"
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
echo "  cliBundlePnpmDepsHash:      $BUNDLE_PNPM_HASH"
echo "  cliCljDepsHash:             $CLJ_DEPS_HASH"
echo "  cliVersion:                 $CLI_VERSION"
echo "  toolchain:                  $OLD_TOOLCHAIN"
echo "  patches:                    $PATCHES_JSON"
