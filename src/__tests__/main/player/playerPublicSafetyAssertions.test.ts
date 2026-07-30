import assert from 'node:assert/strict';
import test from 'node:test';

import { assertPublicSafe } from './playerPublicSafetyAssertions.js';

test('public safety assertion inspects null-prototype records', () => {
  const value = Object.create(null) as Record<string, unknown>;
  value.rawMediaUrl = 'private';

  assert.throws(
    () => assertPublicSafe(value, []),
    /public value included forbidden field rawMediaUrl/u,
  );
});
