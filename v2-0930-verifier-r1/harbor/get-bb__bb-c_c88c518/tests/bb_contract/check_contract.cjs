// Held-out verifier helper. No reference production code or implementation patch.
const fs = require('node:fs');
const crypto = require('node:crypto');
const assert = require('node:assert/strict');
try {
  const parser = '/testbed/node_modules/.pnpm/typescript@5.9.3/node_modules/typescript/lib/typescript.js';
  assert.equal(crypto.createHash('sha256').update(fs.readFileSync(parser)).digest('hex'),
    '3ae902c92cc44dace175c0e69e13a4b0899f6983c6121d76b9ab8dd5795e7675');
  const ts = require(parser);
  const config = require('./read_config.cjs')(ts);
  const result = require('./repository_adapter.cjs').inspectApp({ ts,
    appRoot: '/testbed/apps/app', compilerOptions: config.options });
  process.stdout.write(JSON.stringify({ ...result,
    configurationFiles: config.configurationFiles,
    nativeTypecheckIsSeparate: true }) + '\n');
  // Reporting a violation is an actual rejection, not merely diagnostic output.
  process.exitCode = result.violations.length ? 1 : 0;
} catch (error) {
  console.error(error && error.stack || String(error));
  process.exitCode = 2;
}
