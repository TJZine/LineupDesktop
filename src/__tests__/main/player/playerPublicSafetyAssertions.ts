import assert from 'node:assert/strict';

import {
  PLAYER_FORBIDDEN_PRIVILEGED_FIELD_KEYS,
  hasPlayerForbiddenPrivilegedField,
} from '../../../contracts/player.js';

export function assertPublicSafe(
  value: unknown,
  forbiddenValues: readonly string[],
): void {
  assert.equal(
    hasPlayerForbiddenPrivilegedField(value),
    false,
    `public value included one of ${PLAYER_FORBIDDEN_PRIVILEGED_FIELD_KEYS.join(', ')}`,
  );

  const serialized = JSON.stringify(value) ?? '';
  for (const forbiddenValue of forbiddenValues) {
    assert.equal(
      serialized.includes(forbiddenValue),
      false,
      `public value included private value ${forbiddenValue}`,
    );
  }
}
