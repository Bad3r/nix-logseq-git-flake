{ pkgs }:
pkgs.writeTextFile {
  name = "logseq-desktop";
  destination = "/share/applications/logseq.desktop";
  text = ''
    [Desktop Entry]
    Type=Application
    Name=Logseq
    Exec=logseq %U
    Icon=logseq
    Terminal=false
    Categories=Office;Productivity;
    StartupWMClass=Logseq
    MimeType=x-scheme-handler/logseq;
  '';
}
