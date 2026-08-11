import test from 'node:test';
import assert from 'node:assert/strict';
import {
  cssDeclaration,
  containsCssSelector,
  extractCssAtRuleBody,
  extractCssRule,
} from './cssAtRuleTestUtils.js';

test('at-rule extraction skips a longer prelude and continues to a later exact match', () => {
  const css = [
    '@media (forced-colors: active) and (min-width: 1px) { .partial { color: red; } }',
    '@media (forced-colors: active) { .exact { color: CanvasText; } }',
  ].join('\n');

  assert.equal(
    extractCssAtRuleBody(css, '@media (forced-colors: active)'),
    ' .exact { color: CanvasText; } ',
  );
});

test('at-rule extraction returns null for missing or malformed bodies', () => {
  assert.equal(extractCssAtRuleBody('.rule { color: red; }', '@media (forced-colors: active)'), null);
  assert.equal(extractCssAtRuleBody('@media (forced-colors: active) { .rule { color: red; }', '@media (forced-colors: active)'), null);
});

test('rule extraction compares selector sets and declarations independently of source order', () => {
  const rule = extractCssRule(
    `
      .second,
      .first {
        display: block;
        color: red;
      }
    `,
    ['.first', '.second'],
  );

  assert.equal(cssDeclaration(rule, 'color'), 'red');
  assert.equal(cssDeclaration(rule, 'display'), 'block');
});

test('selector absence is null while unsupported matching declarations fail loudly', () => {
  const source = '.target { color: red; } .other { display: block; }';
  const target = extractCssRule(source, '.target');

  assert.equal(cssDeclaration(target, 'color'), 'red');
  assert.equal(cssDeclaration(target, 'display'), null);
  assert.equal(extractCssRule(source, '.missing'), null);
  assert.throws(() => extractCssRule('.target { color: red;', '.target'), /unmatched rule brace/u);
  assert.throws(() => extractCssRule('.target { .nested { color: red; } }', '.target'), /nested/u);
  assert.throws(() => extractCssRule('.target { color: red; color: blue; }', '.target'), /duplicate/u);
  assert.throws(() => extractCssRule('.target { color; }', '.target'), /malformed declaration/u);
  assert.throws(() => extractCssRule('.target { content: "a;b"; }', '.target'), /string/u);
});

test('selector membership sees grouped selectors and fails on malformed top-level rules', () => {
  const grouped = '.allowed, .player-surface { background: Canvas; }';
  assert.equal(containsCssSelector(grouped, '.player-surface'), true);
  assert.equal(cssDeclaration(extractCssRule(grouped, '.player-surface'), 'background'), 'Canvas');
  assert.equal(containsCssSelector(grouped, '.missing'), false);
  assert.throws(() => containsCssSelector('.allowed { color: red;', '.missing'), /unmatched/u);
});
