// Resolve the candidate's actual JSON/JSONC tsconfig inheritance without
// executing its code or demanding the reference's specific extends layout.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const assert = require('node:assert/strict');

module.exports = function readConfig(ts) {
  const records = new Map();
  let bytesRead = 0;
  const host = {
    useCaseSensitiveFileNames: ts.sys.useCaseSensitiveFileNames,
    getCurrentDirectory: () => '/testbed/apps/app',
    readDirectory: () => [], // Only obtain options; the guard scans all relevant roots.
    directoryExists: ts.sys.directoryExists,
    fileExists: ts.sys.fileExists,
    realpath: ts.sys.realpath,
    onUnRecoverableConfigFileDiagnostic: diagnostic => {
      throw new Error(ts.flattenDiagnosticMessageText(diagnostic.messageText, '\n'));
    },
    readFile(filename) {
      const resolved = path.resolve(filename);
      if (!fs.existsSync(resolved)) return undefined;
      const real = fs.realpathSync(resolved);
      assert(real.startsWith('/testbed/'), `configuration outside repository: ${real}`);
      const data = fs.readFileSync(real);
      bytesRead += data.length;
      assert(data.length <= 65536 && bytesRead <= 256 * 1024, 'configuration read bound');
      if (!records.has(real)) {
        assert(records.size < 24, 'configuration file count bound');
        records.set(real, { path: resolved, realpath: real, bytes: data.length,
          sha256: crypto.createHash('sha256').update(data).digest('hex') });
      }
      return data.toString('utf8');
    },
  };
  const parsed = ts.getParsedCommandLineOfConfigFile('/testbed/apps/app/tsconfig.json', {}, host);
  assert(parsed, 'missing app tsconfig');
  // TS18003 is expected because this options-only host deliberately enumerates
  // no program files. A separate real native tsc command performs typechecking.
  const diagnostics = parsed.errors.filter(item => item.code !== 18003);
  assert.equal(diagnostics.length, 0, diagnostics.map(item =>
    ts.flattenDiagnosticMessageText(item.messageText, '\n')).join('; '));
  return { options: parsed.options, configurationFiles: [...records.values()],
    compilerProgramCreated: false };
};
