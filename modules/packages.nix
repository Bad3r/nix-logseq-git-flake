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
          # Without mainProgram, `nix run` falls back to bin/<name>, and the
          # joined tree ships no bin/logseq-nightly.
          meta = {
            description = "Logseq nightly desktop app and CLI";
            mainProgram = "logseq";
          };
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
