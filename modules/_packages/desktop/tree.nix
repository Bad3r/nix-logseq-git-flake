{
  payload,
  pkgs,
}:
let
  inherit (pkgs.stdenv.hostPlatform) isDarwin isLinux system;
in
if isLinux then
  pkgs.runCommand "logseq-tree" { } ''
    mkdir -p $out/share/logseq
    src="${payload}"
    cp -r "$src/." $out/share/logseq/
    test -x "$out/share/logseq/logseq" \
      || { echo "logseq executable missing at expected path" >&2; exit 1; }
  ''
else if isDarwin then
  pkgs.runCommand "logseq-tree" { } ''
    mkdir -p "$out"
    src="${payload}"
    app_count=$(find "$src" -maxdepth 1 -type d -name '*.app' | wc -l | tr -d ' ')
    if [ "$app_count" != 1 ]; then
      echo "expected exactly one top-level .app bundle in Darwin payload, got $app_count" >&2
      find "$src" -maxdepth 2 -mindepth 1 -print >&2
      exit 1
    fi
    app="$(find "$src" -maxdepth 1 -type d -name '*.app' -print -quit)"
    cp -PRp "$app" "$out/Logseq.app"
    chmod -R u+rwX "$out/Logseq.app"
    test -x "$out/Logseq.app/Contents/MacOS/Logseq" \
      || { echo "Logseq executable missing at expected Darwin app path" >&2; exit 1; }
    test -f "$out/Logseq.app/Contents/Resources/app.asar" \
      || { echo "app.asar missing at expected Darwin app path" >&2; exit 1; }
  ''
else
  throw "logseq desktop tree: unsupported system ${system}"
