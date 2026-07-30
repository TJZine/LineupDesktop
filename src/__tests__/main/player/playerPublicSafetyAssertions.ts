import assert from 'node:assert/strict';

import {
  PLAYER_FORBIDDEN_PRIVILEGED_FIELD_KEYS,
} from '../../../contracts/player.js';

export function assertPublicSafe(
  value: unknown,
  forbiddenValues: readonly string[],
): void {
  assertNoForbiddenPrivilegedFields(value);

  const serialized = JSON.stringify(value) ?? '';
  for (const forbiddenValue of forbiddenValues) {
    assert.equal(
      serialized.includes(forbiddenValue),
      false,
      `public value included private value ${forbiddenValue}`,
    );
  }
}

function assertNoForbiddenPrivilegedFields(value: unknown): void {
  if (value === null || typeof value !== 'object') return;

  for (const [key, child] of Object.entries(value)) {
    assert.equal(
      PLAYER_FORBIDDEN_PRIVILEGED_FIELD_KEYS.includes(
        key as (typeof PLAYER_FORBIDDEN_PRIVILEGED_FIELD_KEYS)[number],
      ),
      false,
      `public value included forbidden field ${key}`,
    );
    assertNoForbiddenPrivilegedFields(child);
  }
}
