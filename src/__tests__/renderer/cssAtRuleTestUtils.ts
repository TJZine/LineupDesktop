/**
 * Test-only scanning for the simple, non-nested rules asserted by Guide tests.
 * Well-formed comments are stripped; strings containing braces/semicolons and
 * any other CSS grammar outside these shapes are unsupported and fail loudly.
 */
export function extractCssAtRuleBody(css: string, atRule: string): string | null {
  const source = stripComments(css);
  let searchStart = 0;
  while (searchStart < source.length) {
    const atRuleIndex = source.indexOf(atRule, searchStart);
    if (atRuleIndex < 0) return null;
    const openBrace = skipWhitespace(source, atRuleIndex + atRule.length);
    if (source[openBrace] !== '{') {
      searchStart = atRuleIndex + atRule.length;
      continue;
    }
    const closeBrace = findMatchingBrace(source, openBrace);
    return closeBrace < 0 ? null : source.slice(openBrace + 1, closeBrace);
  }
  return null;
}
export function extractCssRule(
  css: string,
  expectedSelectors: string | readonly string[],
): ReadonlyMap<string, string> | null {
  const source = stripComments(css);
  const expected = normalizeSelectorSet(
    typeof expectedSelectors === 'string' ? [expectedSelectors] : expectedSelectors,
  );
  if (expected.size === 0) return null;
  let groupedSingleSelectorMatch: ReadonlyMap<string, string> | null = null;
  let cursor = 0;
  while (cursor < source.length) {
    cursor = skipWhitespace(source, cursor);
    if (cursor >= source.length) return groupedSingleSelectorMatch;
    const openBrace = source.indexOf('{', cursor);
    if (openBrace < 0) return groupedSingleSelectorMatch;
    const prelude = source.slice(cursor, openBrace).trim();
    const selectors = normalizeSelectorSet(prelude.split(','));
    const closeBrace = findMatchingBrace(source, openBrace);
    if (closeBrace < 0) {
      if (selectors.size === expected.size && [...expected].every((selector) => selectors.has(selector))) {
        throw unsupported('unmatched rule brace');
      }
      return null;
    }
    cursor = closeBrace + 1;
    // At-rule bodies are scoped by extractCssAtRuleBody before rule scanning.
    if (prelude.startsWith('@')) continue;
    const isSingleSelectorLookup = typeof expectedSelectors === 'string' && expected.size === 1;
    const isExactMatch = selectors.size === expected.size && [...expected].every((selector) => selectors.has(selector));
    if (!isExactMatch && (!isSingleSelectorLookup || ![...expected].every((selector) => selectors.has(selector)))) continue;

    const body = source.slice(openBrace + 1, closeBrace);
    const quoteCount = (body.match(/["']/gu) ?? []).length;
    const stringHasStructure = /"(?:[^"\\]|\\.)*[;{}](?:[^"\\]|\\.)*"/u.test(body)
      || /'(?:[^'\\]|\\.)*[;{}](?:[^'\\]|\\.)*'/u.test(body);
    if (/[{}]/u.test(body) || quoteCount % 2 !== 0 || stringHasStructure) {
      throw unsupported('unsupported nested or string syntax');
    }
    const declarations = parseDeclarations(body);
    if (isExactMatch) return declarations;
    groupedSingleSelectorMatch ??= declarations;
  }
  return groupedSingleSelectorMatch;
}
export function containsCssSelector(css: string, selector: string): boolean {
  const source = stripComments(css);
  const expected = selector.replace(/\s+/gu, ' ').trim();
  let cursor = 0;
  while (cursor < source.length) {
    cursor = skipWhitespace(source, cursor);
    if (cursor >= source.length) return false;
    const openBrace = source.indexOf('{', cursor);
    if (openBrace < 0) throw unsupported('malformed top-level rule');
    const prelude = source.slice(cursor, openBrace).trim();
    const closeBrace = findMatchingBrace(source, openBrace);
    if (closeBrace < 0) throw unsupported('unmatched top-level rule brace');
    const body = source.slice(openBrace + 1, closeBrace);
    cursor = closeBrace + 1;
    if (prelude.startsWith('@')) continue;
    if (body.includes('{')) throw unsupported('nested top-level rule');
    if (normalizeSelectorSet(prelude.split(',')).has(expected)) return true;
  }
  return false;
}
export function cssDeclaration(declarations: ReadonlyMap<string, string> | null, property: string): string | null {
  return declarations?.get(property.trim().toLowerCase()) ?? null;
}
function normalizeSelectorSet(selectors: readonly string[]): Set<string> {
  return new Set(selectors.map((selector) => selector.replace(/\s+/gu, ' ').trim()).filter(Boolean));
}
function parseDeclarations(body: string): ReadonlyMap<string, string> {
  const declarations = new Map<string, string>();
  for (const chunk of body.split(';')) {
    const declaration = chunk.trim();
    if (!declaration) continue;
    const colon = declaration.indexOf(':');
    if (colon < 0) throw unsupported('malformed declaration');
    const property = declaration.slice(0, colon).trim().toLowerCase();
    if (!property || declarations.has(property)) throw unsupported('duplicate or empty declaration');
    declarations.set(property, declaration.slice(colon + 1).trim().replace(/\s+/gu, ' '));
  }
  return declarations;
}
function skipWhitespace(source: string, start: number): number {
  let cursor = start;
  while (cursor < source.length && /\s/u.test(source[cursor] ?? '')) cursor += 1;
  return cursor;
}
function findMatchingBrace(source: string, openBrace: number): number {
  let depth = 0;
  for (let index = openBrace; index < source.length; index += 1) {
    if (source[index] === '{') depth += 1;
    if (source[index] === '}') {
      depth -= 1;
      if (depth === 0) return index;
    }
  }
  return -1;
}
function stripComments(css: string): string {
  return css.replace(/\/\*[\s\S]*?\*\//gu, '');
}
function unsupported(reason: string): Error {
  return new Error(`Unsupported CSS test shape: ${reason}`);
}
