{
  cliBuilt,
  logseqNodejs,
  writeShellScript,
}:
# Two runtime needs the bundled CLI cannot satisfy from an arbitrary cwd:
# - LOGSEQ_DB_WORKER_NODE_SCRIPT: prepare-cli-package.mjs installs the db-worker
#   at static/js/db-worker-node.js, but the CLI's path-relative resolver only
#   checks dist/, dist/js/ and $cwd (server_runtime.ml), so it is not found. Pin
#   upstream's highest-priority override to the worker's absolute path, keeping a
#   caller-provided value if one is set.
# - PATH: the CLI spawns the worker as a bare `node` with shell:false
#   (cli_unix.ml command_args strips the leading "env"), resolved against PATH,
#   so logseqNodejs must be on it.
writeShellScript "logseq-cli-wrapper" ''
  export PATH="${logseqNodejs}/bin''${PATH:+:$PATH}"
  export LOGSEQ_DB_WORKER_NODE_SCRIPT="''${LOGSEQ_DB_WORKER_NODE_SCRIPT:-${cliBuilt}/lib/logseq-cli/static/js/db-worker-node.js}"
  exec ${logseqNodejs}/bin/node "${cliBuilt}/lib/logseq-cli/dist/logseq.js" "$@"
''
