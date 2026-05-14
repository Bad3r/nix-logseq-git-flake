_: {
  perSystem =
    { lib, pkgs, ... }:
    {
      _module.args.logseqNightly = import ./_packages {
        inherit lib pkgs;
        manifestPath = ../data/logseq-nightly.json;
      };
    };
}
