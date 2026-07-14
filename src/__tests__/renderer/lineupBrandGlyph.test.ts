import assert from 'node:assert/strict';
import test from 'node:test';

import { createScopedLineupBrandGlyphMarkup } from '../../renderer/onboarding/lineupBrandGlyph.js';

test('canonical color brand glyph scopes every id and fragment reference per instance', () => {
  const first = createScopedLineupBrandGlyphMarkup();
  const second = createScopedLineupBrandGlyphMarkup();
  const firstIds = [...first.matchAll(/\bid="([^"]+)"/gu)].map((match) => match[1]);
  const secondIds = [...second.matchAll(/\bid="([^"]+)"/gu)].map((match) => match[1]);

  assert.ok(firstIds.length >= 10);
  assert.equal(firstIds.length, new Set(firstIds).size);
  assert.equal(secondIds.length, new Set(secondIds).size);
  assert.equal(firstIds.some((id) => secondIds.includes(id)), false);

  for (const markup of [first, second]) {
    const ids = new Set([...markup.matchAll(/\bid="([^"]+)"/gu)].map((match) => match[1]));
    const references = [...markup.matchAll(/url\(#([^)]+)\)/gu)].map((match) => match[1]);
    assert.ok(references.length >= 10);
    assert.equal(references.every((reference) => ids.has(reference)), true);
    assert.doesNotMatch(markup, /url\(#(?:sh-|rim-|gold-|amber-|steel-)/u);
  }
});
