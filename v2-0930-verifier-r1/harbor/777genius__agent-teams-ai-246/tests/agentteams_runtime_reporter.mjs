// Formal-eval draft version 1; distinct from the diagnostic /work reporter.
// Cached root and MCP Vitest 3.2.6 callback implementations were compared by SHA.
import { writeFile } from 'node:fs/promises';
import path from 'node:path';

function serializeError(error) {
  return {
    name: String(error?.name ?? typeof error),
    message: String(error?.message ?? error).slice(0, 16384),
    stack: typeof error?.stack === 'string' ? error.stack.slice(0, 32768) : null,
  };
}

export default class AgentTeamsRuntimeReporter {
  onInit(ctx) {
    const ignore = ctx.config.dangerouslyIgnoreUnhandledErrors;
    const empty = ctx.config.passWithNoTests;
    if (typeof ignore !== 'boolean' || typeof empty !== 'boolean') {
      throw new Error('Verifier requires explicit boolean runtime and empty-suite flags');
    }
    this.ignoreUnhandledErrors = ignore;
    this.passWithNoTests = empty;
  }

  async onFinished(files, errors) {
    if (!Array.isArray(files) || !Array.isArray(errors)) {
      throw new Error('Unsupported onFinished callback arguments');
    }
    const destination = path.resolve(process.env.SWEPM_RUNTIME_REPORT_PATH ?? '');
    if (!['/logs/verifier/root-runtime-errors.json', '/logs/verifier/mcp-runtime-errors.json'].includes(destination)) {
      throw new Error('Runtime report destination is not an approved verifier log');
    }
    const suiteErrors = [];
    const visit = (task, file) => {
      if (task.type !== 'test') {
        const entries = task.result?.errors ?? [];
        if (!Array.isArray(entries)) throw new Error('Unsupported suite errors shape');
        if (entries.length) suiteErrors.push({file, name: task.name, errors: entries.map(serializeError)});
        for (const child of task.tasks ?? []) visit(child, file);
      }
    };
    for (const file of files) {
      if (typeof file.filepath !== 'string') throw new Error('Missing callback file path');
      visit(file, file.filepath);
    }
    await writeFile(destination, JSON.stringify({
      schema_version: 2,
      helper_version: 'agentteams-formal-runtime-v1',
      source: 'Cached Vitest 3.2.6 onFinished callback arguments and suite result.errors',
      file_paths: files.map(file => file.filepath),
      unhandled_errors_count: errors.length,
      unhandled_errors: errors.map(serializeError),
      runtime_error_suites: suiteErrors.length,
      suite_errors: suiteErrors,
      dangerously_ignore_unhandled_errors: this.ignoreUnhandledErrors,
      pass_with_no_tests: this.passWithNoTests,
      limitation: 'A test-body TypeError remains a failed assertion: manually classify failureMessages.',
    }, null, 2) + '\n', { flag: 'wx' });
  }
}
