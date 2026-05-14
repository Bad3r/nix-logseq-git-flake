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
    "--bind-try"
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
