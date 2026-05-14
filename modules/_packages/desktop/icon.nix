{ logseqSrc, pkgs }:
pkgs.runCommand "logseq-icon" { } ''
  mkdir -p $out/share/icons/hicolor/512x512/apps
  cp ${logseqSrc}/resources/icon.png \
    $out/share/icons/hicolor/512x512/apps/logseq.png
''
