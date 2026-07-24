{
  description = "Nightly Logseq wrapper flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # Dedicated nixpkgs for building the packages (desktop + OCaml/Melange CLI),
    # kept separate from `nixpkgs` so a consumer who overrides this flake's
    # `nixpkgs` (e.g. `inputs.<this>.inputs.nixpkgs.follows` for dedup) cannot
    # re-hash the package closure and miss the Cachix cache. The opam-nix closure
    # is nixpkgs-dependent: building it against a consumer's nixpkgs forces a full
    # local opam-nix `resolve` (import-from-derivation) instead of substituting
    # the prebuilt paths. Packages and the opam toolchain follow this input; only
    # the dev shell, formatter, and check runners use `nixpkgs`. Consumers do not
    # override this input, so they inherit the exact rev CI built and pushed.
    nixpkgs-pinned.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    import-tree.url = "github:denful/import-tree";
    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # OCaml/Melange toolchain for the logseq-cli build. Upstream rewrote the CLI
    # from ClojureScript (shadow-cljs `:logseq-cli`) to OCaml compiled via Melange
    # (logseq/logseq dbd220c95d,
    # https://github.com/logseq/logseq/commit/dbd220c95d). The melange* libraries
    # and the `humanize` git pin are not in nixpkgs, so opam-nix resolves the
    # `cli/logseq-cli.opam` closure. opam-repository is pinned here (not
    # opam-nix's bundled default) so the resolved dependency set moves only on an
    # explicit flake.lock bump.
    opam-nix = {
      url = "github:tweag/opam-nix";
      # Follow nixpkgs-pinned (not nixpkgs) so the resolved OCaml closure stays on
      # the CI-built rev even when a consumer overrides this flake's nixpkgs.
      inputs.nixpkgs.follows = "nixpkgs-pinned";
      inputs.opam-repository.follows = "opam-repository";
    };
    opam-repository = {
      url = "github:ocaml/opam-repository";
      flake = false;
    };
  };

  nixConfig = {
    extra-substituters = [
      "https://nix-logseq-git-flake.cachix.org"
    ];
    extra-trusted-public-keys = [
      "nix-logseq-git-flake.cachix.org-1:DSBNW07PSRyCvS926tpIWahb53OIydwwZhsP6LhJNZo="
    ];
  };

  outputs = inputs: inputs.flake-parts.lib.mkFlake { inherit inputs; } (inputs.import-tree ./modules);
}
