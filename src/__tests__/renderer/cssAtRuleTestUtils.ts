export function extractCssAtRuleBody(css: string, atRule: string): string | null {
  const atRuleIndex = css.indexOf(atRule);
  if (atRuleIndex < 0) return null;
  const openBrace = css.indexOf('{', atRuleIndex + atRule.length);
  if (openBrace < 0) return null;

  let depth = 1;
  for (let index = openBrace + 1; index < css.length; index += 1) {
    if (css[index] === '{') depth += 1;
    if (css[index] === '}') depth -= 1;
    if (depth === 0) return css.slice(openBrace + 1, index);
  }
  return null;
}
