{ manifest, pkgs }:
pkgs.fetchFromGitHub {
  owner = "logseq";
  repo = "logseq";
  rev = manifest.logseqRev;
  hash = manifest.cliSrcHash;
}
