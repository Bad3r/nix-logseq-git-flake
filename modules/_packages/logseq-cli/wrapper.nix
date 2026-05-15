{
  cliBuilt,
  logseqNodejs,
  writeShellScript,
}:
writeShellScript "logseq-cli-wrapper" ''
  # Set up writable cache for nbb-logseq.
  export NBB_CACHE_DIR="''${XDG_CACHE_HOME:-$HOME/.cache}/logseq-cli/nbb"
  mkdir -p "$NBB_CACHE_DIR"

  exec ${logseqNodejs}/bin/node "${cliBuilt}/cli/cli.mjs" "$@"
''
