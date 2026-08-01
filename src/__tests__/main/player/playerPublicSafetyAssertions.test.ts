import assert from 'node:assert/strict';
import test from 'node:test';

import { assertPublicSafe } from './playerPublicSafetyAssertions.js';

test('public safety assertion recursively inspects null-prototype records', () => {
  const value = Object.create(null) as Record<string, unknown>;
  const nested = Object.create(null) as Record<string, unknown>;
  nested.rawMediaUrl = 'private';
  value.details = nested;

  assert.throws(
    () => assertPublicSafe(value, []),
    /public value included forbidden field rawMediaUrl/u,
  );
});
