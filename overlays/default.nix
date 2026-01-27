{
  packages,
}:
final: _prev: {
  logseq-nightly = packages.${final.stdenv.hostPlatform.system} or { };
}
