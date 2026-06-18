{
  description = "Nightly Logseq wrapper flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
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
      inputs.nixpkgs.follows = "nixpkgs";
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
