{ pkgs }:
pkgs.writeTextFile {
  name = "logseq-desktop";
  destination = "/share/applications/logseq.desktop";
  # Categories drops upstream's unregistered "Productivity" value, which
  # desktop-file-validate rejects; compliant menus already showed only Office.
  text = ''
    [Desktop Entry]
    Type=Application
    Name=Logseq
    Exec=logseq %U
    Icon=logseq
    Terminal=false
    Categories=Office;
    StartupWMClass=Logseq
    MimeType=x-scheme-handler/logseq;
  '';
}
