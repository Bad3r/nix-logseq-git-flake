{
  cliBuilt,
  logseqNodejs,
  writeShellScript,
}:
writeShellScript "logseq-cli-wrapper" ''
  exec ${logseqNodejs}/bin/node "${cliBuilt}/lib/logseq-cli/dist/logseq.js" "$@"
''
