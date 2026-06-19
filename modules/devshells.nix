{
  perSystem =
    {
      pkgs,
      logseqHooks,
      logseqNightly,
      ...
    }:
    let
      hookShell = pkgs.mkShell {
        packages = logseqHooks.preCommit.enabledPackages ++ [
          pkgs.coreutils
          pkgs.git
          pkgs.pre-commit
        ];
        inherit (logseqHooks.preCommit) shellHook;
      };
      logseqCliOcamlShell = pkgs.mkShell {
        packages = [
          pkgs.opam
        ]
        ++ logseqNightly.cli.ocamlBuildInputs;
      };
    in
    {
      devShells = {
        default = hookShell;
        # Compatibility alias for older docs/scripts: `nix develop .#hooks`.
        hooks = hookShell;
        logseq-cli-ocaml = logseqCliOcamlShell;
      };
    };
}
