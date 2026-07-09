{
  logseqTree,
  pkgs,
  runtimeLibs,
}:
{
  additionalPkgs ? (_pkgs: [ ]),
}:
pkgs.buildFHSEnv {
  name = "logseq-fhs";
  targetPkgs = pkgs: runtimeLibs pkgs ++ additionalPkgs pkgs;
  extraBwrapArgs = [
    # Read-only unlike the vscode FHS template this copies: vscode binds it
    # read-write to edit system config, but Logseq never writes /etc/nixos.
    "--ro-bind-try"
    "/etc/nixos"
    "/etc/nixos"
    "--ro-bind-try"
    "/etc/xdg"
    "/etc/xdg"
  ];
  extraInstallCommands = ''
    ln -s ${logseqTree}/share $out/share
  '';
  runScript = "${logseqTree}/share/logseq/logseq";
}
