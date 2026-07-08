# Regression guard for the desktop entry: upstream's scripts/install-linux.sh
# ships the unregistered "Productivity" category, which desktop-file-validate
# rejects at error level, so a future re-sync from upstream fails here instead
# of at a compliant menu silently dropping the value.
{ pkgs }:
let
  desktopEntry = import ../_packages/desktop/desktop-entry.nix { inherit pkgs; };
in
pkgs.runCommand "logseq-desktop-entry-check"
  {
    nativeBuildInputs = [ pkgs.desktop-file-utils ];
  }
  ''
    desktop-file-validate "${desktopEntry}/share/applications/logseq.desktop"
    touch $out
  ''
