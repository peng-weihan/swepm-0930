// Draft only: the caller supplies the cached TypeScript parser and source text.
// Parsing never imports, transpiles, evaluates, or executes candidate modules.
const path = require('node:path');

function moduleReferences(ts, filename, text) {
  const ext = path.extname(filename).toLowerCase();
  const kind = ext === '.tsx' ? ts.ScriptKind.TSX : ext === '.jsx'
    ? ts.ScriptKind.JSX : ['.js', '.mjs', '.cjs'].includes(ext)
      ? ts.ScriptKind.JS : ts.ScriptKind.TS;
  const source = ts.createSourceFile(filename, text, ts.ScriptTarget.Latest, true, kind);
  if (source.parseDiagnostics.length) {
    throw new Error(`${filename}: syntax diagnostics: ${source.parseDiagnostics.map(
      d => ts.flattenDiagnosticMessageText(d.messageText, '\n')).join('; ')}`);
  }
  const result = [];
  function add(node, literal, form) {
    if (!literal || !(ts.isStringLiteral(literal) || ts.isNoSubstitutionTemplateLiteral(literal))) return;
    const pos = source.getLineAndCharacterOfPosition(node.getStart(source));
    result.push({ file: filename, line: pos.line + 1, column: pos.character + 1,
      specifier: literal.text, form });
  }
  function visit(node) {
    if (ts.isImportDeclaration(node)) add(node, node.moduleSpecifier, 'import');
    else if (ts.isExportDeclaration(node)) add(node, node.moduleSpecifier, 'export');
    else if (ts.isImportEqualsDeclaration(node) && ts.isExternalModuleReference(node.moduleReference))
      add(node, node.moduleReference.expression, 'import-equals');
    else if (ts.isImportTypeNode(node) && ts.isLiteralTypeNode(node.argument))
      add(node, node.argument.literal, 'import-type');
    else if (ts.isCallExpression(node) && node.expression.kind === ts.SyntaxKind.ImportKeyword)
      add(node, node.arguments[0], 'dynamic-import');
    ts.forEachChild(node, visit);
  }
  visit(source);
  return result;
}

function refersToDeletedBarrel(reference, barrelFile, resolveModule) {
  const barrel = path.resolve(barrelFile);
  const specifier = reference.specifier;
  // The exact public import in the problem must disappear even after the file
  // has been deleted, when ordinary TS resolution necessarily returns undefined.
  if (specifier === '@/components/ui') return true;
  const resolved = resolveModule ? resolveModule(specifier, reference.file) : undefined;
  if (resolved && path.resolve(resolved) === barrel) return true;
  // Preserve recognition of the deleted TS module for existing alias/relative
  // spellings. Do not require formatting, quote style, named imports, or .js on
  // unrelated imports that the problem does not require changing.
  const candidates = new Set([barrel, barrel.slice(0, -3), barrel.slice(0, -3) + '.js', path.dirname(barrel)]);
  if (specifier.startsWith('./') || specifier.startsWith('../'))
    return candidates.has(path.resolve(path.dirname(reference.file), specifier));
  if (specifier.startsWith('@/components/ui/')) {
    const suffix = specifier.slice('@/components/ui/'.length);
    return ['index', 'index.ts', 'index.js'].includes(suffix);
  }
  return false;
}

function auditModules({ ts, modules, barrelFile, barrelExists, resolveModule }) {
  const violations = [];
  if (barrelExists) violations.push({ file: barrelFile, rule: 'explicitly-deleted-file-present' });
  for (const { filename, text } of modules) {
    for (const reference of moduleReferences(ts, filename, text)) {
      if (refersToDeletedBarrel(reference, barrelFile, resolveModule))
        violations.push({ ...reference, rule: 'consumer-of-deleted-barrel' });
    }
  }
  return { checkedFiles: modules.length, violations };
}

module.exports = { moduleReferences, refersToDeletedBarrel, auditModules };
