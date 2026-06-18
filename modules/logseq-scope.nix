{ inputs, ... }:
{
  perSystem =
    {
      lib,
      pkgs,
      system,
      ...
    }:
    {
      _module.args.logseqNightly = import ./_packages/logseq-nightly.nix {
        inherit lib pkgs system;
        manifestPath = ../data/logseq-nightly.json;
        opamNix = inputs.opam-nix;
      };
    };
}
