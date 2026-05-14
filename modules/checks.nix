{
  perSystem =
    { pkgs, logseqNightly, ... }:
    {
      checks = {
        logseq-runtime-assets = import ./_checks/runtime-assets.nix {
          inherit pkgs;
          inherit (logseqNightly) payload logseqSrc;
        };

        logseq = pkgs.runCommand "logseq-check" { } ''
          ${pkgs.coreutils}/bin/test -x ${logseqNightly.logseqDesktop}/bin/logseq
          touch $out
        '';

        logseq-cli = pkgs.runCommand "logseq-cli-check" { } ''
          ${pkgs.coreutils}/bin/test -x ${logseqNightly.cli}/bin/logseq-cli
          touch $out
        '';

        logseq-cli-help = import ./_checks/cli-help.nix {
          inherit pkgs;
          inherit (logseqNightly) cli;
        };
      };
    };
}
