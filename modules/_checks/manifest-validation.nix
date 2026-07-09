# Regression guard for lib/loadManifest.nix error behavior: every malformed
# manifest below must fail with a manifest-shaped throw, which tryEval can
# catch. A raw Nix type error (hasAttr/hasPrefix reaching a mistyped value)
# is uncatchable and aborts this check's evaluation, which is exactly the
# regression this guards against. Forcing the result to WHNF runs every
# validator: loadManifest wraps parsed in nested throwIf conditionals.
{ lib, pkgs }:
let
  inherit (builtins)
    attrNames
    fromJSON
    isString
    readFile
    removeAttrs
    toFile
    toJSON
    tryEval
    ;
  base = fromJSON (readFile ../../data/logseq-nightly.json);
  load =
    manifest:
    import ../../lib/loadManifest.nix {
      inherit lib;
      manifestPath = toFile "manifest-under-test.json" (toJSON manifest);
    };
  rejects = manifest: !(tryEval (load manifest)).success;
  cases = {
    topLevelArray = [ ];
    missingKey = removeAttrs base [ "tag" ];
    numericHash = base // {
      cliSrcHash = 42;
    };
    stringAssets = base // {
      assets = "oops";
    };
    stringAssetEntry = base // {
      assets = base.assets // {
        x86_64-linux = "oops";
      };
    };
    nonSriAssetHash = base // {
      assets = base.assets // {
        x86_64-linux = base.assets.x86_64-linux // {
          sha256 = "abc123";
        };
      };
    };
    rawPlusAssetUrl = base // {
      assets = base.assets // {
        x86_64-linux = base.assets.x86_64-linux // {
          url = "https://github.com/Bad3r/nix-logseq-git-flake/releases/download/nightly-20260630/logseq-linux-x64-2.0.1-alpha+nightly.20260630.tar.gz";
        };
      };
    };
    listVersion = base // {
      logseqVersion = [ "2.0.0" ];
    };
    stringPinOverride = base // {
      cliOpamPinOverrides = [ "oops" ];
    };
    branchRefPinOverride = base // {
      cliOpamPinOverrides = [
        {
          from = "a";
          to = "https://example.com/repo.git#main";
        }
      ];
    };
    stringPatchEntry = base // {
      patches = [ "logseq-fix.patch" ];
    };
    traversalPatchFile = base // {
      patches = [
        {
          file = "logseq-../evil.patch";
          cli = false;
        }
      ];
    };
    numericToolchain = base // {
      toolchain = base.toolchain // {
        node = 22;
      };
    };
  };
  accepted = lib.filter (name: !rejects cases.${name}) (attrNames cases);
in
lib.throwIf (accepted != [ ])
  "loadManifest accepted malformed manifests: ${lib.concatStringsSep ", " accepted}"
  (
    lib.throwIf (!isString (load base).tag) "loadManifest rejected the current manifest." (
      pkgs.runCommand "logseq-manifest-validation-check" { } ''
        touch $out
      ''
    )
  )
