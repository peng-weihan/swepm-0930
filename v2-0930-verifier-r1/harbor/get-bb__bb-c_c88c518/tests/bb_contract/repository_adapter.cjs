// Diagnostic draft, not installed in the formal verifier.
// This adapter reads source and resolves module paths but never imports candidate code.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const { auditModules } = require('./ui-barrel-contract.cjs');
const sha = b => crypto.createHash('sha256').update(b).digest('hex');
const suffixes = new Set(['.ts', '.tsx', '.mts', '.cts', '.js', '.jsx', '.mjs', '.cjs']);

// Module resolution only: model the one deleted file as present so that TS can
// still identify imports referring to it after deletion. Nothing is materialized,
// no exports are invented, and no candidate module is executed or typechecked.
function deletedBarrelResolver({ ts, appRoot, barrelFile, compilerOptions, host = ts.sys }) {
  const isDeleted = filename => path.resolve(filename) === path.resolve(barrelFile);
  const resolverHost = {
    fileExists: filename => isDeleted(filename) || host.fileExists(filename),
    readFile: filename => isDeleted(filename) ? '' : host.readFile(filename),
    directoryExists: host.directoryExists?.bind(host),
    realpath: filename => isDeleted(filename) ? path.resolve(barrelFile)
      : host.realpath ? host.realpath(filename) : filename,
    getCurrentDirectory: () => appRoot,
    getDirectories: host.getDirectories?.bind(host),
  };
  return (specifier, importer) => ts.resolveModuleName(
    specifier, importer, compilerOptions, resolverHost).resolvedModule?.resolvedFileName;
}

function inspectApp({ ts, appRoot, compilerOptions }) {
  appRoot = fs.realpathSync(appRoot);
  const barrelFile = path.join(appRoot, 'src/components/ui/index.ts');
  const modules = [];
  const inventory = [];
  const roots = [];
  let sourceBytes = 0;
  function visit(filename) {
    const st = fs.lstatSync(filename);
    // Current base/gold has no source symlinks. A later symlink requires an
    // explicit traversal review; do not silently skip it or call it acceptance.
    assert(!st.isSymbolicLink(), `unreviewed source symlink: ${filename}`);
    if (st.isDirectory()) {
      for (const name of fs.readdirSync(filename).sort()) visit(path.join(filename, name));
      return;
    }
    assert(st.isFile(), `not a regular source: ${filename}`);
    if (!suffixes.has(path.extname(filename))) return;
    const bytes = fs.readFileSync(filename);
    sourceBytes += bytes.length;
    assert(sourceBytes <= 16 * 1024 * 1024 && modules.length < 2000, 'source inspection bound');
    modules.push({ filename, text: bytes.toString('utf8') });
    inventory.push({ path: path.relative(appRoot, filename), bytes: bytes.length, sha256: sha(bytes) });
  }
  for (const name of ['src', 'test', 'tests', 'fixtures', 'stories']) {
    const root = path.join(appRoot, name);
    if (fs.existsSync(root)) { roots.push(name); visit(root); }
  }
  assert(roots.includes('src') && modules.length > 0, 'app source is absent');
  let barrelExists;
  try { fs.lstatSync(barrelFile); barrelExists = true; }
  catch (e) { if (e.code !== 'ENOENT') throw e; barrelExists = false; }
  const resolveModule = deletedBarrelResolver({ ts, appRoot, barrelFile, compilerOptions });
  const result = auditModules({ ts, modules, barrelFile, barrelExists, resolveModule });
  return { ...result, appRoot, scannedRoots: roots, sourceBytes, sourceInventory: inventory,
    ignoresTypecheckExcludePatterns: true, candidateCodeExecuted: false,
    typecheckExecuted: false, unresolvedComputedImportsOutOfScope: true };
}

module.exports = { inspectApp, deletedBarrelResolver };
