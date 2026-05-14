_: {
  perSystem =
    { lib, pkgs, ... }:
    {
      _module.args.logseqNightly = import ./_packages/scope.nix {
        inherit lib pkgs;
        manifestPath = ../data/logseq-nightly.json;
      };
    };
}
