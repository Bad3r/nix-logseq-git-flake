{
  lib,
  logseqTree,
  manifest,
  pkgs,
}:
pkgs.stdenv.mkDerivation {
  pname = "logseq-desktop";
  version = manifest.logseqVersion;
  dontUnpack = true;

  nativeBuildInputs = [
    pkgs.darwin.sigtool
  ];

  buildCommand = ''
    app="$out/Applications/Logseq.app"
    mkdir -p "$out/Applications" "$out/bin"
    cp -PRp ${logseqTree}/Logseq.app "$app"
    chmod -R u+rwX "$app"

    if [ -x /usr/bin/codesign ]; then
      /usr/bin/codesign --force --deep --sign - "$app"
    else
      codesign --force --deep --sign - "$app"
    fi

    ln -s "$app/Contents/MacOS/Logseq" "$out/bin/logseq"
  '';

  meta = with lib; {
    description = "Logseq nightly desktop app";
    homepage = "https://github.com/logseq/logseq";
    license = licenses.agpl3Plus;
    platforms = [ "aarch64-darwin" ];
    mainProgram = "logseq";
  };
}
