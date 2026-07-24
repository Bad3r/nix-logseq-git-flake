{ inputs, ... }:
{
  perSystem =
    {
      lib,
      system,
      ...
    }:
    let
      # Build every package against nixpkgs-pinned, a separate input consumers do
      # not override. This keeps the nixpkgs-dependent opam-nix/Melange closure on
      # the rev CI built and pushed to Cachix, so a consumer's `nixpkgs` override
      # (dedup) can no longer re-hash the packages and force a local opam-nix
      # `resolve`. The flake's overridable `pkgs` still drives the dev shell,
      # formatter, and check runners.
      pkgsPinned = inputs.nixpkgs-pinned.legacyPackages.${system};
    in
    {
      _module.args = {
        inherit pkgsPinned;
        logseqNightly = import ./_packages/logseq-nightly.nix {
          inherit lib system;
          pkgs = pkgsPinned;
          manifestPath = ../data/logseq-nightly.json;
          opamNix = inputs.opam-nix;
        };
      };
    };
}
