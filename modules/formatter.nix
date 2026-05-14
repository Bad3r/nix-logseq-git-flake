{
  perSystem =
    { logseqHooks, ... }:
    {
      formatter = logseqHooks.preCommit.config.hooks.treefmt.package;
    };
}
