{
  perSystem =
    {
      lib,
      pkgs,
      logseqNightly,
      ...
    }:
    let
      inherit (pkgs.stdenv.hostPlatform) isDarwin;
    in
    {
      checks = {
        logseq-manifest-validation = import ./_checks/manifest-validation.nix {
          inherit lib pkgs;
        };

        logseq-runtime-assets = import ./_checks/runtime-assets.nix {
          inherit pkgs;
          inherit (logseqNightly) payload logseqSrc;
        };

        logseq =
          pkgs.runCommand "logseq-check"
            {
              nativeBuildInputs = lib.optionals isDarwin [
                pkgs.darwin.sigtool
              ];
            }
            (
              if isDarwin then
                ''
                  app="${logseqNightly.logseqDesktop}/Applications/Logseq.app"
                  ${pkgs.coreutils}/bin/test -d "$app"
                  ${pkgs.coreutils}/bin/test -x "$app/Contents/MacOS/Logseq"
                  ${pkgs.coreutils}/bin/test -f "$app/Contents/Resources/app.asar"
                  ${pkgs.coreutils}/bin/test -x ${logseqNightly.logseqDesktop}/bin/logseq
                  if [ -x /usr/bin/codesign ]; then
                    /usr/bin/codesign --verify --deep --strict "$app"
                  else
                    codesign --verify --deep --strict "$app"
                  fi
                  touch $out
                ''
              else
                ''
                  ${pkgs.coreutils}/bin/test -x ${logseqNightly.logseqDesktop}/bin/logseq
                  touch $out
                ''
            );

        logseq-cli = pkgs.runCommand "logseq-cli-check" { } ''
          ${pkgs.coreutils}/bin/test -x ${logseqNightly.cli}/bin/logseq-cli
          touch $out
        '';

        logseq-cli-help = import ./_checks/cli-help.nix {
          inherit pkgs;
          inherit (logseqNightly) cli;
        };

        logseq-cli-login-callback = import ./_checks/cli-login-callback.nix {
          inherit pkgs;
          inherit (logseqNightly) cli;
        };

        logseq-cli-graph-query = import ./_checks/cli-graph-query.nix {
          inherit pkgs;
          inherit (logseqNightly) cli;
        };
      }
      # The desktop entry ships only in the Linux package.
      // lib.optionalAttrs (!isDarwin) {
        logseq-desktop-entry = import ./_checks/desktop-entry.nix { inherit pkgs; };
      };
    };
}
