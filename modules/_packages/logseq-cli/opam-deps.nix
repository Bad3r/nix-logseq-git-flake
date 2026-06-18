{
  opamNix,
  pkgs,
  src,
  system,
}:
# Resolve the OCaml/Melange dependency closure for the upstream `cli/` dune
# project. logseq/logseq dbd220c95d
# (https://github.com/logseq/logseq/commit/dbd220c95d) migrated the CLI from
# ClojureScript to OCaml compiled via Melange. The melange* libraries and the
# `humanize` git pin (cli/logseq-cli.opam pin-depends) are absent from nixpkgs,
# so opam-nix builds each dependency from the pinned opam-repository (flake
# input) as its own derivation. OCaml is pinned to 5.4.0 to match upstream's
# OCAML_VERSION (.github/workflows/deps-cli.yml / build-desktop-release.yml).
#
# buildOpamProject reads the committed cli/logseq-cli.opam (do not use
# buildDuneProject: it bootstraps opam-file generation with a dune older than the
# `(lang dune 3.23)` cli/dune-project declares, which aborts). It returns a
# package scope; dune >= 3.23 is pulled in as a resolved dependency. The flake
# does not build the project's @install target (that omits the Vite bundle step);
# build.nix instead runs `dune build @bundle` with this closure on PATH/OCAMLPATH.
# opam-nix derivations carry setup hooks that assemble OCAMLPATH across propagated
# deps, so dune resolves melange.ppx/js/node and the in-tree virtual spec library
# compiles from source.
let
  on = opamNix.lib.${system};
  baseScope = on.buildOpamProject { inherit pkgs; } "logseq-cli" "${src}/cli" {
    ocaml-base-compiler = "5.4.0";
  };
  # melc locates its own stdlib relative to its binary: `melc -where` yields
  # $out/lib/melange/{melange,js/melange}. opam-nix installs OCaml libraries
  # under OCAMLFIND_DESTDIR ($out/lib/ocaml/<ver>/site-lib) instead.
  scope = baseScope.overrideScope (
    _final: prev: {
      melange = prev.melange.overrideAttrs (old: {
        postInstall = (old.postInstall or "") + ''
          if [ ! -d "$OCAMLFIND_DESTDIR/melange" ]; then
            echo "melange: $OCAMLFIND_DESTDIR/melange missing; cannot create the lib/melange compat link" >&2
            exit 1
          fi
          ln -s "$OCAMLFIND_DESTDIR/melange" "$out/lib/melange"
        '';
      });
    }
  );
in
{
  ocamlBuildInputs = [
    scope.ocaml
    scope.dune
    scope.melange
    scope.melange-fetch
    scope.melange-transit
    scope.melange-edn
    scope.melange-fest
    scope.humanize
  ];
}
