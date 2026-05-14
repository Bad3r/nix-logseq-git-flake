{
  desktopEntry,
  fhsBase,
  icon,
  launcher,
  lib,
  logseqFhs,
  logseqTree,
  manifest,
  pkgs,
}:
pkgs.stdenv.mkDerivation {
  pname = "logseq-desktop";
  version = manifest.logseqVersion;
  dontUnpack = true;
  buildCommand = ''
    mkdir -p $out
    cp -r --no-preserve=mode,ownership ${logseqTree}/share $out/
    cp -r --no-preserve=mode,ownership ${icon}/share $out/
    cp -r --no-preserve=mode,ownership ${desktopEntry}/share $out/
    mkdir -p $out/bin
    ln -s ${launcher}/bin/logseq $out/bin/logseq
  '';
  meta = with lib; {
    description = "Logseq nightly desktop app";
    homepage = "https://github.com/logseq/logseq";
    license = licenses.agpl3Plus;
    platforms = platforms.linux;
    mainProgram = "logseq";
  };
  passthru = {
    fhs = logseqFhs;
    fhsWithPackages = fhsBase;
  };
}
