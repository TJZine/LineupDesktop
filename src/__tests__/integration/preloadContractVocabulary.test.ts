import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import ts from 'typescript';

import { PLAYER_RENDERER_INTENTS } from '../../contracts/ipc.js';
import {
  PLAYER_COMMAND_VALUES,
  PLAYER_ERROR_CATEGORIES,
  PLAYER_FORBIDDEN_PRIVILEGED_FIELD_KEYS,
  PLAYER_STATUS_VALUES,
  PLAYER_TRACK_DELIVERY_TYPE_VALUES,
  PLAYER_TRACK_KIND_VALUES,
} from '../../contracts/player.js';
import { SHELL_STATUS_VALUES } from '../../contracts/shell.js';

const preloadSourceUrl = new URL('../../preload/index.cts', import.meta.url);
const preloadSourceText = readFileSync(preloadSourceUrl, 'utf8');
const preloadSourceFile = ts.createSourceFile(
  'src/preload/index.cts',
  preloadSourceText,
  ts.ScriptTarget.Latest,
  true,
  ts.ScriptKind.TS,
);

function readPreloadStringArrayConst(name: string): string[] {
  let values: string[] | null = null;

  function visit(node: ts.Node): void {
    if (values !== null || !ts.isVariableStatement(node)) {
      ts.forEachChild(node, visit);
      return;
    }

    for (const declaration of node.declarationList.declarations) {
      if (
        ts.isIdentifier(declaration.name) &&
        declaration.name.text === name &&
        declaration.initializer !== undefined
      ) {
        values = readStringArrayInitializer(name, declaration.initializer);
        return;
      }
    }
  }

  visit(preloadSourceFile);
  assert.ok(values, `expected ${name} in preload entrypoint`);
  return values;
}

function readStringArrayInitializer(name: string, initializer: ts.Expression): string[] {
  const expression = ts.isAsExpression(initializer) ? initializer.expression : initializer;
  assert.ok(ts.isArrayLiteralExpression(expression), `expected ${name} to be an array literal`);
  return expression.elements.map((element) => {
    assert.ok(ts.isStringLiteral(element), `expected ${name} to contain only string literals`);
    return element.text;
  });
}

test('preload guard vocabulary matches contract vocabulary', () => {
  assert.doesNotMatch(preloadSourceText, /\.\/vocabulary\.cjs/u);
  assert.deepEqual(readPreloadStringArrayConst('SHELL_STATUS_VALUES'), [...SHELL_STATUS_VALUES]);
  assert.deepEqual(readPreloadStringArrayConst('PLAYER_ERROR_CATEGORIES'), [...PLAYER_ERROR_CATEGORIES]);
  assert.deepEqual(
    readPreloadStringArrayConst('PLAYER_FORBIDDEN_PRIVILEGED_FIELD_KEYS'),
    [...PLAYER_FORBIDDEN_PRIVILEGED_FIELD_KEYS],
  );
  assert.deepEqual(readPreloadStringArrayConst('PLAYER_STATUS_VALUES'), [...PLAYER_STATUS_VALUES]);
  assert.deepEqual(readPreloadStringArrayConst('PLAYER_COMMAND_VALUES'), [...PLAYER_COMMAND_VALUES]);
  assert.deepEqual(readPreloadStringArrayConst('PLAYER_RENDERER_INTENT_VALUES'), [
    ...PLAYER_RENDERER_INTENTS,
  ]);
  assert.deepEqual(readPreloadStringArrayConst('PLAYER_TRACK_KIND_VALUES'), [
    ...PLAYER_TRACK_KIND_VALUES,
  ]);
  assert.deepEqual(
    readPreloadStringArrayConst('PLAYER_TRACK_DELIVERY_TYPE_VALUES'),
    [...PLAYER_TRACK_DELIVERY_TYPE_VALUES],
  );
});
