{ inputs, ... }:
{
  perSystem =
    {
      lib,
      pkgs,
      system,
      ...
    }:
    let
      hooks = import ./_hooks {
        inherit (inputs)
          git-hooks
          ;
        inherit
          lib
          pkgs
          system
          ;
      };
    in
    {
      _module.args.logseqHooks = hooks;
      checks.pre-commit-check = hooks.preCommit;
    };
}
