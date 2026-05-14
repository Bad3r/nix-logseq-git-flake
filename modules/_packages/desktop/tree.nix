{ payload, pkgs }:
pkgs.runCommand "logseq-tree" { } ''
  mkdir -p $out/share/logseq
  src="${payload}"
  cp -r "$src/." $out/share/logseq/
  test -x "$out/share/logseq/logseq" \
    || { echo "logseq executable missing at expected path" >&2; exit 1; }
''
