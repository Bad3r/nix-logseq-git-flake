# Cache PATH from nix develop for fast/non-devshell hook execution.
if [ -n "${IN_NIX_SHELL:-}" ]; then
  return 0 2>/dev/null || true
fi

# Use git-path so this works in both regular repos and git worktrees.
CACHE_DIR=$(git rev-parse --git-path lefthook-cache 2>/dev/null || echo ".git/lefthook-cache")
CACHE_FILE="$CACHE_DIR/path.sh"
HASH_FILE="$CACHE_DIR/flake.lock.hash"

mkdir -p "$CACHE_DIR" 2>/dev/null || true

current_hash=""
hash_inputs=""
if [ -f "flake.nix" ]; then
  hash_inputs="$hash_inputs flake.nix"
fi
if [ -f "flake.lock" ]; then
  hash_inputs="$hash_inputs flake.lock"
fi
if [ -n "$hash_inputs" ]; then
  # Hash both flake manifest and lock to refresh cached PATH when tool inputs change.
  current_hash=$(sha256sum $hash_inputs 2>/dev/null | sha256sum | cut -d' ' -f1)
fi

needs_update=1
if [ -f "$CACHE_FILE" ] && [ -f "$HASH_FILE" ]; then
  cached_hash=$(cat "$HASH_FILE" 2>/dev/null || echo "")
  if [ "$current_hash" = "$cached_hash" ] && [ -n "$current_hash" ]; then
    needs_update=0
  fi
fi

if [ "$needs_update" = "1" ]; then
  nix_path=$(nix develop .#hooks --accept-flake-config -c sh -c 'echo "$PATH"' 2>/dev/null || true)
  if [ -n "$nix_path" ]; then
    echo "export PATH=\"$nix_path\"" >"$CACHE_FILE"
    echo "$current_hash" >"$HASH_FILE"
  else
    return 0 2>/dev/null || true
  fi
fi

if [ -f "$CACHE_FILE" ]; then
  . "$CACHE_FILE"
fi
