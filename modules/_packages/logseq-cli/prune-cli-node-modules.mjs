// Populate <cli-package-dir>/node_modules with only the runtime dependency
// closure declared by the generated cli-package package.json, copied out of
// the monorepo's pnpm install in the current working directory.
//
// The full workspace node_modules also carries every dev/build dependency
// (electron, webpack, vite, ...), an order of magnitude more than the CLI
// needs at runtime. A fresh `pnpm install --prod` of the generated package
// cannot run here: offline resolution lacks registry metadata, and two CLI
// runtime deps (better-sqlite3, ws) live in upstream's root devDependencies,
// so a --prod filter would drop them. Instead, walk pnpm's virtual store:
// every package dir under node_modules/.pnpm/<id>/node_modules/ has its
// resolved dependencies materialized as sibling symlinks, so the reachable
// realpath set from the declared dependency names is the exact runtime
// closure pnpm itself resolved.
import fs from "node:fs";
import path from "node:path";

const packageRoot = process.argv[2];
if (!packageRoot) {
  throw new Error("usage: prune-cli-node-modules.mjs <cli-package-dir>");
}
const sourceModules = path.resolve("node_modules");
const targetModules = path.join(packageRoot, "node_modules");

const manifest = JSON.parse(
  fs.readFileSync(path.join(packageRoot, "package.json"), "utf8"),
);
const required = Object.keys(manifest.dependencies ?? {});
const optional = Object.keys(manifest.optionalDependencies ?? {});

// Nearest ancestor directory literally named node_modules; handles scoped
// package dirs (.../node_modules/@scope/name) needing two hops.
const siblingRoot = (dir) => {
  let current = dir;
  while (path.basename(current) !== "node_modules") {
    const parent = path.dirname(current);
    if (parent === current) {
      throw new Error(`no node_modules ancestor for ${dir}`);
    }
    current = parent;
  }
  return current;
};

// .pnpm/<id>/node_modules/<name...> -> .pnpm/<id>, failing loudly if a
// dependency resolves outside the virtual store (e.g. a workspace link, which
// no registry package can legitimately depend on).
const pnpmIdDir = (pkgDir) => {
  const idDir = path.dirname(siblingRoot(pkgDir));
  if (path.basename(path.dirname(idDir)) !== ".pnpm") {
    throw new Error(`dependency resolved outside the pnpm store: ${pkgDir}`);
  }
  return idDir;
};

const queue = [];
const topLevel = [];
const skippedOptional = [];
for (const name of [...required, ...optional]) {
  const link = path.join(sourceModules, name);
  if (!fs.existsSync(link)) {
    // Platform-gated optional deps (e.g. @zvec/bindings-* for other systems)
    // are absent from the install on purpose, exactly as npm would skip them.
    if (optional.includes(name)) {
      skippedOptional.push(name);
      continue;
    }
    throw new Error(`missing required CLI runtime dependency: ${name}`);
  }
  if (!fs.lstatSync(link).isSymbolicLink()) {
    throw new Error(`expected a pnpm symlink at ${link}`);
  }
  topLevel.push(name);
  queue.push(fs.realpathSync(link));
}

const seen = new Set();
while (queue.length > 0) {
  const pkgDir = queue.pop();
  if (seen.has(pkgDir)) continue;
  seen.add(pkgDir);
  const moduleDir = siblingRoot(pkgDir);
  for (const entry of fs.readdirSync(moduleDir)) {
    if (entry === ".bin") continue;
    const entryPath = path.join(moduleDir, entry);
    const links = entry.startsWith("@")
      ? fs.readdirSync(entryPath).map((sub) => path.join(entryPath, sub))
      : [entryPath];
    for (const candidate of links) {
      if (fs.lstatSync(candidate).isSymbolicLink()) {
        queue.push(fs.realpathSync(candidate));
      }
    }
  }
}

const idDirs = new Set([...seen].map(pnpmIdDir));
fs.mkdirSync(path.join(targetModules, ".pnpm"), { recursive: true });
for (const idDir of idDirs) {
  fs.cpSync(idDir, path.join(targetModules, ".pnpm", path.basename(idDir)), {
    recursive: true,
    verbatimSymlinks: true,
  });
}

// Recreate the package's own top-level links with their original relative
// targets, which stay valid because the copied .pnpm tree mirrors the layout.
for (const name of topLevel) {
  const destination = path.join(targetModules, name);
  fs.mkdirSync(path.dirname(destination), { recursive: true });
  fs.symlinkSync(fs.readlinkSync(path.join(sourceModules, name)), destination);
}

for (const name of required) {
  if (!fs.existsSync(path.join(targetModules, name, "package.json"))) {
    throw new Error(`pruned tree does not resolve required dep: ${name}`);
  }
}

console.log(
  `pruned node_modules: ${idDirs.size} packages for ${topLevel.length} declared deps` +
    (skippedOptional.length > 0
      ? `; skipped absent optionals: ${skippedOptional.join(", ")}`
      : ""),
);
