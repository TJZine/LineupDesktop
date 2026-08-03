export interface CssRule {
  selector: string;
  declarations: string;
  atRules: readonly string[];
}

export function normalizeCss(css: string): string {
  return css.replace(/\r\n?/gu, '\n');
}

export function extractCssRule(
  css: string,
  selector: string,
  options: { atRule?: string; declaration?: string } = {},
): CssRule | null {
  const expectedSelector = normalizeSelector(selector);
  const matches = parseCssRules(normalizeCss(css)).filter((rule) =>
    splitSelectorList(rule.selector).some((candidate) => normalizeSelector(candidate) === expectedSelector) &&
    (options.atRule === undefined || rule.atRules.includes(options.atRule)),
  );
  const declaration = options.declaration;
  if (declaration !== undefined) {
    return matches.find((rule) => cssDeclaration(rule, declaration) !== null) ?? null;
  }
  return matches.find((rule) => normalizeSelector(rule.selector) === expectedSelector) ?? matches[0] ?? null;
}

export function cssDeclaration(rule: CssRule | null, property: string): string | null {
  if (rule === null) return null;
  const expectedProperty = property.trim().toLowerCase();
  let effectiveValue: string | null = null;
  for (const declaration of splitTopLevel(rule.declarations, ';')) {
    const colon = findTopLevelCharacter(declaration, ':');
    if (colon < 0) continue;
    const name = declaration.slice(0, colon).trim().toLowerCase();
    if (name === expectedProperty) {
      effectiveValue = declaration.slice(colon + 1).trim().replace(/\s+/gu, ' ');
    }
  }
  return effectiveValue;
}

function parseCssRules(css: string): CssRule[] {
  const source = css.replace(/\/\*[\s\S]*?\*\//gu, '');
  const rules: CssRule[] = [];
  collectRules(source, 0, source.length, [], rules);
  return rules;
}

function collectRules(
  source: string,
  start: number,
  end: number,
  atRules: readonly string[],
  output: CssRule[],
): void {
  let cursor = start;
  while (cursor < end) {
    cursor = skipWhitespace(source, cursor, end);
    if (cursor >= end) return;
    const delimiter = findTopLevelDelimiter(source, cursor, end);
    if (delimiter < 0) return;
    const prelude = source.slice(cursor, delimiter).trim();
    if (source[delimiter] === ';') {
      cursor = delimiter + 1;
      continue;
    }
    const close = findMatchingBrace(source, delimiter, end);
    if (close < 0) return;
    if (prelude.startsWith('@')) {
      collectRules(source, delimiter + 1, close, [...atRules, prelude], output);
    } else if (prelude.length > 0) {
      output.push({
        selector: prelude,
        declarations: source.slice(delimiter + 1, close).trim(),
        atRules,
      });
    }
    cursor = close + 1;
  }
}

function splitSelectorList(selector: string): string[] {
  return splitTopLevel(selector, ',').map((part) => part.trim()).filter(Boolean);
}

function normalizeSelector(selector: string): string {
  return selector.replace(/\s+/gu, ' ').trim();
}

function splitTopLevel(value: string, delimiter: string): string[] {
  const parts: string[] = [];
  let start = 0;
  let parentheses = 0;
  let brackets = 0;
  let quote: string | null = null;
  for (let index = 0; index < value.length; index += 1) {
    const character = value[index];
    if (quote !== null) {
      if (character === '\\') index += 1;
      else if (character === quote) quote = null;
      continue;
    }
    if (character === '"' || character === "'") {
      quote = character;
    } else if (character === '(') {
      parentheses += 1;
    } else if (character === ')' && parentheses > 0) {
      parentheses -= 1;
    } else if (character === '[') {
      brackets += 1;
    } else if (character === ']' && brackets > 0) {
      brackets -= 1;
    } else if (character === delimiter && parentheses === 0 && brackets === 0) {
      parts.push(value.slice(start, index));
      start = index + 1;
    }
  }
  parts.push(value.slice(start));
  return parts;
}

function findTopLevelCharacter(value: string, expected: string): number {
  let parentheses = 0;
  let brackets = 0;
  let quote: string | null = null;
  for (let index = 0; index < value.length; index += 1) {
    const character = value[index];
    if (quote !== null) {
      if (character === '\\') index += 1;
      else if (character === quote) quote = null;
      continue;
    }
    if (character === '"' || character === "'") quote = character;
    else if (character === '(') parentheses += 1;
    else if (character === ')' && parentheses > 0) parentheses -= 1;
    else if (character === '[') brackets += 1;
    else if (character === ']' && brackets > 0) brackets -= 1;
    else if (character === expected && parentheses === 0 && brackets === 0) return index;
  }
  return -1;
}

function skipWhitespace(source: string, start: number, end: number): number {
  let cursor = start;
  while (cursor < end && /\s/u.test(source[cursor] ?? '')) cursor += 1;
  return cursor;
}

function findTopLevelDelimiter(source: string, start: number, end: number): number {
  let parentheses = 0;
  let quote: string | null = null;
  for (let index = start; index < end; index += 1) {
    const character = source[index];
    if (quote !== null) {
      if (character === '\\') index += 1;
      else if (character === quote) quote = null;
      continue;
    }
    if (character === '"' || character === "'") quote = character;
    else if (character === '(') parentheses += 1;
    else if (character === ')' && parentheses > 0) parentheses -= 1;
    else if (parentheses === 0 && (character === '{' || character === ';')) return index;
  }
  return -1;
}

function findMatchingBrace(source: string, open: number, end: number): number {
  let depth = 0;
  let quote: string | null = null;
  for (let index = open; index < end; index += 1) {
    const character = source[index];
    if (quote !== null) {
      if (character === '\\') index += 1;
      else if (character === quote) quote = null;
      continue;
    }
    if (character === '"' || character === "'") {
      quote = character;
    } else if (character === '{') {
      depth += 1;
    } else if (character === '}') {
      depth -= 1;
      if (depth === 0) return index;
    }
  }
  return -1;
}
