{ self, ... }:
{
  perSystem =
    { pkgs, logseqNightly, ... }:
    {
      packages = {
        logseq = logseqNightly.logseqDesktop;
        logseq-cli = logseqNightly.cli;
        default = pkgs.symlinkJoin {
          name = "logseq-nightly";
          paths = [
            logseqNightly.logseqDesktop
            logseqNightly.cli
          ];
        };
      };

      apps.logseq = {
        type = "app";
        program = "${logseqNightly.logseqDesktop}/bin/logseq";
        meta = {
          description = "Launch the nightly Logseq build packaged from the upstream master branch";
          homepage = "https://github.com/logseq/logseq";
          source = self.outPath;
        };
      };
    };
}
