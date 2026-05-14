_: {
  perSystem =
    { lib, pkgs, ... }:
    {
      _module.args.logseqNightly = import ./_packages/logseq-nightly.nix {
        inherit lib pkgs;
        manifestPath = ../data/logseq-nightly.json;
      };
    };
}
