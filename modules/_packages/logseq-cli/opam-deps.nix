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
# git pins (cli/logseq-cli.opam pin-depends: humanize, rrbvec, ...) are absent
# from nixpkgs, so opam-nix builds each dependency from the pinned
# opam-repository (flake input) as its own derivation. OCaml is pinned to 5.4.0
# to match upstream's OCAML_VERSION (.github/workflows/deps-cli.yml /
# build-desktop-release.yml).
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
  projectName = "logseq-cli";
  baseScope = on.buildOpamProject { inherit pkgs; } projectName "${cliProject}" {
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
  # Take the closure from the resolved root package rather than naming each
  # library: buildInputs is opam-nix's own mapping of cli/logseq-cli.opam
  # `depends:` onto scope entries, so a dependency upstream adds reaches
  # `dune build @bundle` without an edit here. A hand-listed set dropped
  # `rrbvec` (logseq/logseq 322cb65ac4), failing every nightly from 2026-07-13
  # with `Error: Library "rrbvec" not found`. Unresolvable names come back null.
  closure = builtins.filter (dep: dep != null) scope.${projectName}.buildInputs;
  # These entries are structural to `dune build @bundle`; fail during
  # evaluation if one stops landing in the resolved root package inputs.
  missing = lib.subtractLists (map lib.getName closure) [
    "ocaml"
    "dune"
    "melange"
  ];
in
lib.throwIf (missing != [ ])
  "opam-nix did not resolve ${lib.concatStringsSep ", " missing} for ${projectName}; check cli/logseq-cli.opam depends:."
  {
    ocamlBuildInputs = closure;
  }
