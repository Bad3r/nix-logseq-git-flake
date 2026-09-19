#!/usr/bin/env bash
# install-cachix.sh: cachix-action installCommand that never builds cachix.
#
# cachix.org's installer URL intermittently fails DNS on macOS runners (#49), so
# cachix comes from the flake-pinned nixpkgs instead. That input follows
# nixos-unstable, which advances on Linux gates only, so a locked rev can lack
# the aarch64-darwin binary. Nix then compiles cachix from source and the job
# dies at its 60 minute timeout (validate-aarch64-darwin run 35402171727,
# cache-cli-aarch64 in nightly run 34737860128). Use the pinned nixpkgs only
# when its binary is substitutable; otherwise install from FALLBACK_REV.
#
# FALLBACK_REV must have cachix cached for x86_64-linux, aarch64-linux, and
# aarch64-darwin. Check a candidate with:
#   nix path-info --store https://cache.nixos.org \
#     "$(nix eval --raw github:NixOS/nixpkgs/<rev>#legacyPackages.<system>.cachix.outPath)"

set -euo pipefail

: "${GITHUB_WORKSPACE:?must be set}"

FALLBACK_REV="8ce4ef6cb6f871616146b9fe26d2a5ae594e94fe"

pinned_path="$(nix eval --raw --inputs-from "$GITHUB_WORKSPACE" nixpkgs#cachix.outPath)"

if nix path-info --store https://cache.nixos.org "$pinned_path" >/dev/null 2>&1; then
  echo "cachix: installing ${pinned_path} from the flake-pinned nixpkgs"
  nix profile install --inputs-from "$GITHUB_WORKSPACE" nixpkgs#cachix
else
  echo "cachix: ${pinned_path} is not in cache.nixos.org for this system;" \
    "installing from nixpkgs ${FALLBACK_REV} instead of building from source" >&2
  nix profile install "github:NixOS/nixpkgs/${FALLBACK_REV}#cachix"
fi
