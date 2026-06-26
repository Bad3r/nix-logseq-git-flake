{
  cliOpamPinOverrides,
  lib,
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
  # Upstream cli/logseq-cli.opam (since logseq/logseq 3684727952e6) pins some
  # pin-depends (melange-edn, humanize, ...) at a mutable `#main` branch. opam-nix's
  # fetchGitURL refuses a git pin whose fragment is not a 40-char sha1 in pure
  # evaluation mode and throws "[opam-nix] a git dependency without an explicit
  # sha1 is not supported in pure evaluation mode". Native opam (the desktop build
  # legs) accepts the branch ref, so only this opam-nix path needs explicit revs.
  # scripts/update-nightly.sh resolves each branch ref to its current commit and
  # records the rewrites in manifest.cliOpamPinOverrides ({from,to} URL pairs), so
  # the pin advances with logseqRev every nightly instead of freezing. Apply those
  # rewrites before opam-nix reads the file. When the override list is empty (every
  # pin already a sha1) the project is read in place, unchanged.
  pinRewrites = lib.concatMapStringsSep "\n" (
    o:
    "substituteInPlace \"$out/logseq-cli.opam\" --replace-fail ${lib.escapeShellArg o.from} ${lib.escapeShellArg o.to}"
  ) cliOpamPinOverrides;
  cliProject =
    if cliOpamPinOverrides == [ ] then
      "${src}/cli"
    else
      pkgs.runCommandLocal "logseq-cli-opam-project" { } ''
        cp -R ${src}/cli "$out"
        chmod -R u+w "$out"
        ${pinRewrites}
      '';
  baseScope = on.buildOpamProject { inherit pkgs; } "logseq-cli" "${cliProject}" {
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
