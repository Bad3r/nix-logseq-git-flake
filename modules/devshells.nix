{
  perSystem =
    { pkgs, logseqHooks, ... }:
    let
      hookShell = pkgs.mkShell {
        packages = logseqHooks.preCommit.enabledPackages ++ [
          pkgs.coreutils
          pkgs.git
          pkgs.pre-commit
        ];
        inherit (logseqHooks.preCommit) shellHook;
      };
    in
    {
      devShells = {
        default = hookShell;
        # Compatibility alias for older docs/scripts: `nix develop .#hooks`.
        hooks = hookShell;
      };
    };
}
