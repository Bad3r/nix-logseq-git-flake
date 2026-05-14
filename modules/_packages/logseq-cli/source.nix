{
  cliSrcHash,
  fetchFromGitHub,
  logseqRev,
}:
fetchFromGitHub {
  owner = "logseq";
  repo = "logseq";
  rev = logseqRev;
  hash = cliSrcHash;
}
