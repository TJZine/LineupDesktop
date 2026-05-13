import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import ts from 'typescript';

import {
  LINEUP_PLAYER_CLEANUP_CHANNEL,
  LINEUP_PLAYER_COMMAND_CHANNEL,
  LINEUP_PLAYER_EVENT_CHANNEL,
  LINEUP_PLAYER_GET_SNAPSHOT_CHANNEL,
  LINEUP_SHELL_GET_CAPABILITIES_CHANNEL,
  LINEUP_SHELL_STATUS_CHANGED_CHANNEL,
  LINEUP_WINDOW_INTENT_CHANNEL,
  LINEUP_DIAGNOSTICS_EXPORT_SUPPORT_BUNDLE_CHANNEL,
  LINEUP_DIAGNOSTICS_GET_SUMMARY_CHANNEL,
  LINEUP_DIAGNOSTICS_RECORD_RENDERER_EVENT_CHANNEL,
  PLAYER_RENDERER_INTENTS,
} from '../../contracts/ipc.js';
import {
  DIAGNOSTIC_CATEGORIES,
  DIAGNOSTIC_SEVERITIES,
  DIAGNOSTIC_STATUSES,
  DIAGNOSTIC_SURFACES,
  DIAGNOSTICS_ERROR_CODES,
  DIAGNOSTICS_REQUEST_ID_PATTERN_SOURCE,
  DIAGNOSTICS_RENDERER_EVENT_CATEGORIES,
  DIAGNOSTICS_RENDERER_EVENT_SEVERITIES,
  DIAGNOSTICS_UNSAFE_RENDERER_CONTEXT_VALUE_PATTERN_SOURCE,
  REDACTION_SCAN_FINDING_LABELS,
} from '../../contracts/diagnostics.js';
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

const APPROVED_PRELOAD_CHANNEL_CONSTANTS = {
  LINEUP_SHELL_GET_CAPABILITIES_CHANNEL,
  LINEUP_WINDOW_INTENT_CHANNEL,
  LINEUP_SHELL_STATUS_CHANGED_CHANNEL,
  LINEUP_PLAYER_COMMAND_CHANNEL,
  LINEUP_PLAYER_GET_SNAPSHOT_CHANNEL,
  LINEUP_PLAYER_CLEANUP_CHANNEL,
  LINEUP_PLAYER_EVENT_CHANNEL,
  LINEUP_DIAGNOSTICS_RECORD_RENDERER_EVENT_CHANNEL,
  LINEUP_DIAGNOSTICS_GET_SUMMARY_CHANNEL,
  LINEUP_DIAGNOSTICS_EXPORT_SUPPORT_BUNDLE_CHANNEL,
} as const;

const APPROVED_IPC_CHANNELS_BY_METHOD = {
  invoke: new Set([
    'LINEUP_SHELL_GET_CAPABILITIES_CHANNEL',
    'LINEUP_WINDOW_INTENT_CHANNEL',
    'LINEUP_PLAYER_COMMAND_CHANNEL',
    'LINEUP_PLAYER_GET_SNAPSHOT_CHANNEL',
    'LINEUP_PLAYER_CLEANUP_CHANNEL',
    'LINEUP_DIAGNOSTICS_RECORD_RENDERER_EVENT_CHANNEL',
    'LINEUP_DIAGNOSTICS_GET_SUMMARY_CHANNEL',
    'LINEUP_DIAGNOSTICS_EXPORT_SUPPORT_BUNDLE_CHANNEL',
  ]),
  on: new Set(['LINEUP_SHELL_STATUS_CHANGED_CHANNEL', 'LINEUP_PLAYER_EVENT_CHANNEL']),
  removeListener: new Set([
    'LINEUP_SHELL_STATUS_CHANGED_CHANNEL',
    'LINEUP_PLAYER_EVENT_CHANNEL',
  ]),
} as const;

const APPROVED_IPC_METHODS = new Set(Object.keys(APPROVED_IPC_CHANNELS_BY_METHOD));

function readPreloadStringArrayConst(name: string): string[] {
  const declaration = findPreloadVariableDeclaration(name);
  assert.ok(declaration?.initializer, `expected ${name} in preload entrypoint`);
  return readStringArrayInitializer(name, declaration.initializer);
}

function findPreloadVariableDeclaration(name: string): ts.VariableDeclaration | null {
  let result: ts.VariableDeclaration | null = null;

  function visit(node: ts.Node): void {
    if (result !== null) {
      return;
    }
    if (ts.isVariableDeclaration(node) && ts.isIdentifier(node.name) && node.name.text === name) {
      result = node;
      return;
    }
    ts.forEachChild(node, visit);
  }

  visit(preloadSourceFile);
  return result;
}

function findPreloadFunctionDeclaration(name: string): ts.FunctionDeclaration | null {
  let result: ts.FunctionDeclaration | null = null;

  function visit(node: ts.Node): void {
    if (result !== null) {
      return;
    }
    if (ts.isFunctionDeclaration(node) && node.name?.text === name) {
      result = node;
      return;
    }
    ts.forEachChild(node, visit);
  }

  visit(preloadSourceFile);
  return result;
}

function readStringArrayInitializer(name: string, initializer: ts.Expression): string[] {
  const expression = unwrapExpression(initializer);
  assert.ok(ts.isArrayLiteralExpression(expression), `expected ${name} to be an array literal`);
  return expression.elements.map((element) => {
    assert.ok(ts.isStringLiteral(element), `expected ${name} to contain only string literals`);
    return element.text;
  });
}

function readStringConstInitializer(name: string, initializer: ts.Expression): string {
  const expression = unwrapExpression(initializer);
  assert.ok(ts.isStringLiteral(expression), `expected ${name} to be a string literal`);
  return expression.text;
}

function unwrapExpression(expression: ts.Expression): ts.Expression {
  let current = expression;
  while (
    ts.isAsExpression(current) ||
    ts.isSatisfiesExpression(current) ||
    ts.isParenthesizedExpression(current)
  ) {
    current = current.expression;
  }
  return current;
}

function collectPreloadChannelConstants(): Map<string, string> {
  const constants = new Map<string, string>();

  function visit(node: ts.Node): void {
    if (
      ts.isVariableDeclaration(node) &&
      ts.isIdentifier(node.name) &&
      node.name.text.endsWith('_CHANNEL')
    ) {
      assert.ok(node.initializer, `${node.name.text} must have a string initializer`);
      assert.ok(
        isTopLevelConstDeclaration(node),
        `${node.name.text} must be a top-level const channel declaration`,
      );
      assert.equal(
        constants.has(node.name.text),
        false,
        `${node.name.text} must not be redeclared`,
      );
      constants.set(node.name.text, readStringConstInitializer(node.name.text, node.initializer));
    }
    ts.forEachChild(node, visit);
  }

  visit(preloadSourceFile);
  return constants;
}

function collectContextBridgeExposureCalls(): ts.CallExpression[] {
  const calls: ts.CallExpression[] = [];

  function visit(node: ts.Node): void {
    assertNoForbiddenElectronAccess(node);

    if (ts.isIdentifier(node) && node.text === 'contextBridge') {
      assert.ok(
        isApprovedContextBridgeIdentifierUse(node),
        `contextBridge aliasing or direct exposure is not allowed: ${describeNode(node.parent)}`,
      );
    }

    if (
      ts.isElementAccessExpression(node) &&
      ts.isIdentifier(node.expression) &&
      node.expression.text === 'contextBridge'
    ) {
      assert.fail(`contextBridge dynamic access is not allowed: ${describeNode(node)}`);
    }

    if (
      ts.isPropertyAccessExpression(node) &&
      ts.isIdentifier(node.expression) &&
      node.expression.text === 'contextBridge' &&
      node.name.text !== 'exposeInMainWorld'
    ) {
      assert.fail(`contextBridge.${node.name.text} is not an approved preload exposure`);
    }

    if (
      ts.isCallExpression(node) &&
      ts.isPropertyAccessExpression(node.expression) &&
      ts.isIdentifier(node.expression.expression) &&
      node.expression.expression.text === 'contextBridge' &&
      node.expression.name.text === 'exposeInMainWorld'
    ) {
      calls.push(node);
    }
    ts.forEachChild(node, visit);
  }

  visit(preloadSourceFile);
  return calls;
}

function describeNode(node: ts.Node, sourceFile = preloadSourceFile): string {
  return node.getText(sourceFile).replaceAll(/\s+/gu, ' ');
}

function assertNoElectronValueImports(sourceFile = preloadSourceFile): void {
  function visit(node: ts.Node): void {
    if (
      ts.isImportDeclaration(node) &&
      ts.isStringLiteral(node.moduleSpecifier) &&
      node.moduleSpecifier.text === 'electron' &&
      node.importClause !== undefined &&
      !isTypeOnlyImportClause(node.importClause)
    ) {
      assert.fail(`Electron value imports are not allowed in preload: ${describeNode(node, sourceFile)}`);
    }
    ts.forEachChild(node, visit);
  }

  visit(sourceFile);
}

function isTypeOnlyImportClause(importClause: ts.ImportClause): boolean {
  if (importClause.isTypeOnly) {
    return true;
  }
  if (importClause.name !== undefined) {
    return false;
  }
  const namedBindings = importClause.namedBindings;
  return (
    namedBindings !== undefined &&
    ts.isNamedImports(namedBindings) &&
    namedBindings.elements.length > 0 &&
    namedBindings.elements.every((element) => element.isTypeOnly)
  );
}

function isTopLevelConstDeclaration(node: ts.VariableDeclaration): boolean {
  return (
    node.initializer !== undefined &&
    (node.parent.flags & ts.NodeFlags.Const) !== 0 &&
    ts.isVariableStatement(node.parent.parent) &&
    ts.isSourceFile(node.parent.parent.parent)
  );
}

function isElectronRequireBinding(node: ts.Identifier): boolean {
  if (
    !ts.isBindingElement(node.parent) ||
    node.parent.name !== node ||
    !ts.isObjectBindingPattern(node.parent.parent)
  ) {
    return false;
  }

  const declaration = node.parent.parent.parent;
  return ts.isVariableDeclaration(declaration) && isApprovedElectronRequireDeclaration(declaration);
}

function isElectronRequireCall(node: ts.Node): node is ts.CallExpression {
  return (
    ts.isCallExpression(node) &&
    ts.isIdentifier(node.expression) &&
    node.expression.text === 'require' &&
    node.arguments.length === 1 &&
    ts.isStringLiteral(node.arguments[0]) &&
    node.arguments[0].text === 'electron'
  );
}

function isApprovedElectronRequireCall(node: ts.CallExpression): boolean {
  let parent = node.parent;
  while (ts.isAsExpression(parent) || ts.isParenthesizedExpression(parent)) {
    parent = parent.parent;
  }

  return ts.isVariableDeclaration(parent) && isApprovedElectronRequireDeclaration(parent);
}

function isApprovedElectronRequireDeclaration(declaration: ts.VariableDeclaration): boolean {
  return (
    declaration.initializer !== undefined &&
    (declaration.parent.flags & ts.NodeFlags.Const) !== 0 &&
    ts.isVariableStatement(declaration.parent.parent) &&
    ts.isSourceFile(declaration.parent.parent.parent) &&
    isElectronRequireCall(unwrapExpression(declaration.initializer)) &&
    ts.isObjectBindingPattern(declaration.name) &&
    declaration.name.elements.length === 2 &&
    declaration.name.elements[0] !== undefined &&
    declaration.name.elements[1] !== undefined &&
    isExactElectronBindingElement(declaration.name.elements[0], 'contextBridge') &&
    isExactElectronBindingElement(declaration.name.elements[1], 'ipcRenderer')
  );
}

function isExactElectronBindingElement(element: ts.BindingElement, name: string): boolean {
  return (
    element.propertyName === undefined &&
    element.dotDotDotToken === undefined &&
    ts.isIdentifier(element.name) &&
    element.name.text === name &&
    element.initializer === undefined
  );
}

function hasElectronRequireExpression(node: ts.Expression): boolean {
  const expression = unwrapExpression(node);
  if (isElectronRequireCall(expression)) {
    return true;
  }
  if (ts.isPropertyAccessExpression(expression) || ts.isElementAccessExpression(expression)) {
    return hasElectronRequireExpression(expression.expression);
  }
  return false;
}

function isApprovedIpcRendererIdentifierUse(node: ts.Identifier): boolean {
  return (
    isElectronRequireBinding(node) ||
    (ts.isPropertyAccessExpression(node.parent) &&
      node.parent.expression === node &&
      ts.isCallExpression(node.parent.parent) &&
      node.parent.parent.expression === node.parent)
  );
}

function isApprovedContextBridgeIdentifierUse(node: ts.Identifier): boolean {
  return (
    isElectronRequireBinding(node) ||
    (ts.isPropertyAccessExpression(node.parent) &&
      node.parent.expression === node &&
      node.parent.name.text === 'exposeInMainWorld' &&
      ts.isCallExpression(node.parent.parent) &&
      node.parent.parent.expression === node.parent)
  );
}

function collectBindingIdentifiers(name: string): ts.Identifier[] {
  const bindings: ts.Identifier[] = [];

  function visit(node: ts.Node): void {
    if (ts.isIdentifier(node) && node.text === name && isBindingIdentifier(node)) {
      bindings.push(node);
    }
    ts.forEachChild(node, visit);
  }

  visit(preloadSourceFile);
  return bindings;
}

function isBindingIdentifier(node: ts.Identifier): boolean {
  const parent = node.parent;
  return (
    (ts.isVariableDeclaration(parent) && parent.name === node) ||
    (ts.isBindingElement(parent) && parent.name === node) ||
    (ts.isParameter(parent) && parent.name === node) ||
    (ts.isFunctionDeclaration(parent) && parent.name === node) ||
    (ts.isClassDeclaration(parent) && parent.name === node) ||
    (ts.isTypeAliasDeclaration(parent) && parent.name === node) ||
    (ts.isInterfaceDeclaration(parent) && parent.name === node) ||
    (ts.isImportSpecifier(parent) && parent.name === node) ||
    (ts.isImportClause(parent) && parent.name === node) ||
    (ts.isNamespaceImport(parent) && parent.name === node)
  );
}

function assertApprovedChannelIdentifier(name: string): void {
  assert.ok(
    Object.hasOwn(APPROVED_PRELOAD_CHANNEL_CONSTANTS, name),
    `${name} is not an approved preload channel constant`,
  );
  const bindings = collectBindingIdentifiers(name);
  assert.equal(bindings.length, 1, `${name} must have exactly one binding`);

  const declaration = findPreloadVariableDeclaration(name);
  assert.ok(declaration, `${name} must be declared in preload source`);
  assert.ok(isTopLevelConstDeclaration(declaration), `${name} must be a top-level const`);
  assert.ok(declaration.initializer, `${name} must have a string initializer`);
  assert.equal(
    readStringConstInitializer(name, declaration.initializer),
    APPROVED_PRELOAD_CHANNEL_CONSTANTS[name as keyof typeof APPROVED_PRELOAD_CHANNEL_CONSTANTS],
    `${name} must match ipc.ts`,
  );
}

function assertApprovedElectronRequireBinding(): void {
  const declarations: ts.VariableDeclaration[] = [];

  function visit(node: ts.Node): void {
    if (
      ts.isVariableDeclaration(node) &&
      node.initializer !== undefined &&
      isElectronRequireCall(unwrapExpression(node.initializer))
    ) {
      declarations.push(node);
    }
    ts.forEachChild(node, visit);
  }

  visit(preloadSourceFile);
  assert.equal(declarations.length, 1, 'expected exactly one Electron require binding');
  assert.ok(
    isApprovedElectronRequireDeclaration(declarations[0]),
    'expected exact top-level const { contextBridge, ipcRenderer } = require("electron") binding',
  );
}

function assertNoForbiddenElectronAccess(node: ts.Node): void {
  if (ts.isCallExpression(node) && isElectronRequireCall(node)) {
    assert.ok(
      isApprovedElectronRequireCall(node),
      `Electron require must stay as the approved destructured binding: ${describeNode(node.parent)}`,
    );
  }

  if (
    (ts.isPropertyAccessExpression(node) || ts.isElementAccessExpression(node)) &&
    hasElectronRequireExpression(node.expression)
  ) {
    assert.fail(`Dynamic Electron member access is not allowed: ${describeNode(node)}`);
  }
}

test('preload guard vocabulary matches contract vocabulary', () => {
  assert.doesNotMatch(preloadSourceText, /\.\/vocabulary\.cjs/u);
  assert.equal(
    preloadSourceText.includes(
      `const DIAGNOSTICS_REQUEST_ID_PATTERN = /${DIAGNOSTICS_REQUEST_ID_PATTERN_SOURCE}/u;`,
    ),
    true,
  );
  assert.equal(
    preloadSourceText.includes(
      `/${DIAGNOSTICS_UNSAFE_RENDERER_CONTEXT_VALUE_PATTERN_SOURCE}/iu`,
    ),
    true,
  );
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
  assert.deepEqual(readPreloadStringArrayConst('DIAGNOSTIC_SURFACES'), [
    ...DIAGNOSTIC_SURFACES,
  ]);
  assert.deepEqual(readPreloadStringArrayConst('DIAGNOSTIC_CATEGORIES'), [
    ...DIAGNOSTIC_CATEGORIES,
  ]);
  assert.deepEqual(readPreloadStringArrayConst('DIAGNOSTIC_SEVERITIES'), [
    ...DIAGNOSTIC_SEVERITIES,
  ]);
  assert.deepEqual(readPreloadStringArrayConst('DIAGNOSTIC_STATUSES'), [
    ...DIAGNOSTIC_STATUSES,
  ]);
  assert.deepEqual(readPreloadStringArrayConst('DIAGNOSTICS_RENDERER_EVENT_CATEGORIES'), [
    ...DIAGNOSTICS_RENDERER_EVENT_CATEGORIES,
  ]);
  assert.deepEqual(readPreloadStringArrayConst('DIAGNOSTICS_RENDERER_EVENT_SEVERITIES'), [
    ...DIAGNOSTICS_RENDERER_EVENT_SEVERITIES,
  ]);
  assert.deepEqual(readPreloadStringArrayConst('DIAGNOSTICS_ERROR_CODES'), [
    ...DIAGNOSTICS_ERROR_CODES,
  ]);
  assert.deepEqual(readPreloadStringArrayConst('REDACTION_SCAN_FINDING_LABELS'), [
    ...REDACTION_SCAN_FINDING_LABELS,
  ]);
});

test('preload diagnostics guards validate count map keys and values', () => {
  assert.equal(
    preloadSourceText.includes(
      'function isFiniteNonNegativeNumberMap(value: unknown, allowedKeys: readonly string[]): boolean {',
    ),
    true,
  );
  assert.match(
    preloadSourceText,
    /hasOnlyKeys\(value, \[\], allowedKeys\) &&\s*Object\.values\(value\)\.every\(isFiniteNonNegativeNumber\)/u,
  );
  assert.equal(
    preloadSourceText.includes('isFiniteNonNegativeNumberMap(value.surfaceCounts, DIAGNOSTIC_SURFACES)'),
    true,
  );
  assert.equal(
    preloadSourceText.includes('isFiniteNonNegativeNumberMap(value.severityCounts, DIAGNOSTIC_SEVERITIES)'),
    true,
  );
  assert.equal(
    preloadSourceText.includes('isFiniteNonNegativeNumberMap(value.findingsByLabel, REDACTION_SCAN_FINDING_LABELS)'),
    true,
  );
});

test('preload diagnostics result guard validates cancellation discriminator exactly', () => {
  const declaration = findPreloadFunctionDeclaration('isDiagnosticsResult');
  assert.ok(declaration, 'expected preload diagnostics result guard to be declared');

  const source = declaration.getText(preloadSourceFile);
  assert.match(
    source,
    /const hasValidCancellationFlag = value\.cancelled === undefined \|\| value\.cancelled === true;/u,
  );
  assert.match(
    source,
    /hasOnlyKeys\(value, \['ok', 'requestId', 'error'\], \['cancelled'\]\) &&\s*hasValidCancellationFlag && isDiagnosticsError\(value\.error\)/u,
  );
  assert.doesNotMatch(source, /typeof value\.cancelled === 'boolean'/u);
});

test('preload channel constants match approved IPC contract exports', () => {
  const preloadChannelConstants = collectPreloadChannelConstants();
  assert.deepEqual(
    [...preloadChannelConstants.keys()].sort(),
    Object.keys(APPROVED_PRELOAD_CHANNEL_CONSTANTS).sort(),
  );

  for (const [name, expectedValue] of Object.entries(APPROVED_PRELOAD_CHANNEL_CONSTANTS)) {
    assertApprovedChannelIdentifier(name);
    assert.equal(preloadChannelConstants.get(name), expectedValue, `${name} must match ipc.ts`);
  }
});

test('preload bridge guard rejects Electron value imports while allowing type imports', () => {
  const typeOnlySource = ts.createSourceFile(
    'fixture.cts',
    [
      "import type { IpcRendererEvent } from 'electron';",
      "import { type BrowserWindowConstructorOptions } from 'electron';",
      'const event: IpcRendererEvent | null = null;',
      'const options: BrowserWindowConstructorOptions | null = null;',
      'void event;',
      'void options;',
    ].join('\n'),
    ts.ScriptTarget.Latest,
    true,
    ts.ScriptKind.TS,
  );
  assert.doesNotThrow(() => assertNoElectronValueImports(typeOnlySource));

  const valueImportSource = ts.createSourceFile(
    'fixture.cts',
    [
      "import { ipcRenderer as unsafeIpc } from 'electron';",
      "unsafeIpc.invoke('lineup:unsafe');",
    ].join('\n'),
    ts.ScriptTarget.Latest,
    true,
    ts.ScriptKind.TS,
  );
  assert.throws(
    () => assertNoElectronValueImports(valueImportSource),
    /Electron value imports are not allowed in preload/u,
  );
});

test('preload bridge exposes only the typed lineupDesktop world', () => {
  assertNoElectronValueImports();
  assertApprovedElectronRequireBinding();

  const exposureCalls = collectContextBridgeExposureCalls();
  assert.equal(exposureCalls.length, 1, 'expected exactly one contextBridge exposure');

  const [exposureCall] = exposureCalls;
  const [worldKey, exposedValue] = exposureCall.arguments;
  assert.ok(ts.isStringLiteral(worldKey), 'expected exposed world key to be a string literal');
  assert.equal(worldKey.text, 'lineupDesktop');
  assert.ok(ts.isIdentifier(exposedValue), 'expected exposed value to be an identifier');
  assert.equal(exposedValue.text, 'lineupDesktop');
  assert.equal(
    collectBindingIdentifiers('lineupDesktop').length,
    1,
    'expected exactly one lineupDesktop binding',
  );

  const bridgeDeclaration = findPreloadVariableDeclaration('lineupDesktop');
  assert.ok(bridgeDeclaration, 'expected typed lineupDesktop bridge object');
  assert.ok(
    bridgeDeclaration.parent.flags & ts.NodeFlags.Const,
    'expected lineupDesktop bridge object to be const',
  );
  assert.ok(
    bridgeDeclaration.type !== undefined &&
      ts.isTypeReferenceNode(bridgeDeclaration.type) &&
      ts.isIdentifier(bridgeDeclaration.type.typeName) &&
      bridgeDeclaration.type.typeName.text === 'LineupDesktopPreloadApi',
    'expected lineupDesktop bridge object to be typed as LineupDesktopPreloadApi',
  );
  assert.ok(
    bridgeDeclaration.initializer !== undefined &&
      ts.isObjectLiteralExpression(unwrapExpression(bridgeDeclaration.initializer)),
    'expected lineupDesktop bridge object to be an object literal',
  );
});

test('preload bridge uses ipcRenderer only through approved methods and channels', () => {
  assertNoElectronValueImports();
  assertApprovedElectronRequireBinding();

  const observedCalls: string[] = [];

  function visit(node: ts.Node): void {
    assertNoForbiddenElectronAccess(node);

    if (ts.isIdentifier(node) && node.text === 'ipcRenderer') {
      assert.ok(
        isApprovedIpcRendererIdentifierUse(node),
        `ipcRenderer aliasing or direct exposure is not allowed: ${describeNode(node.parent)}`,
      );
    }

    if (
      ts.isElementAccessExpression(node) &&
      ts.isIdentifier(node.expression) &&
      node.expression.text === 'ipcRenderer'
    ) {
      assert.fail(`ipcRenderer dynamic access is not allowed: ${describeNode(node)}`);
    }

    if (
      ts.isPropertyAccessExpression(node) &&
      ts.isIdentifier(node.expression) &&
      node.expression.text === 'ipcRenderer'
    ) {
      assert.ok(ts.isCallExpression(node.parent) && node.parent.expression === node);
      const methodName = node.name.text;
      assert.ok(
        APPROVED_IPC_METHODS.has(methodName),
        `ipcRenderer.${methodName} is not an approved preload bridge method`,
      );

      const [channelExpression] = node.parent.arguments;
      assert.ok(channelExpression, `ipcRenderer.${methodName} must pass an explicit channel`);
      assert.ok(
        ts.isIdentifier(channelExpression),
        `ipcRenderer.${methodName} channel must be an approved constant identifier, got ${describeNode(
          channelExpression,
        )}`,
      );

      const approvedChannels =
        APPROVED_IPC_CHANNELS_BY_METHOD[
          methodName as keyof typeof APPROVED_IPC_CHANNELS_BY_METHOD
        ];
      assert.ok(
        approvedChannels.has(channelExpression.text),
        `ipcRenderer.${methodName} is not approved for ${channelExpression.text}`,
      );
      assertApprovedChannelIdentifier(channelExpression.text);
      observedCalls.push(`${methodName}:${channelExpression.text}`);
    }

    ts.forEachChild(node, visit);
  }

  visit(preloadSourceFile);

  assert.deepEqual(observedCalls.sort(), [
    'invoke:LINEUP_DIAGNOSTICS_EXPORT_SUPPORT_BUNDLE_CHANNEL',
    'invoke:LINEUP_DIAGNOSTICS_GET_SUMMARY_CHANNEL',
    'invoke:LINEUP_DIAGNOSTICS_RECORD_RENDERER_EVENT_CHANNEL',
    'invoke:LINEUP_PLAYER_CLEANUP_CHANNEL',
    'invoke:LINEUP_PLAYER_COMMAND_CHANNEL',
    'invoke:LINEUP_PLAYER_GET_SNAPSHOT_CHANNEL',
    'invoke:LINEUP_SHELL_GET_CAPABILITIES_CHANNEL',
    'invoke:LINEUP_WINDOW_INTENT_CHANNEL',
    'on:LINEUP_PLAYER_EVENT_CHANNEL',
    'on:LINEUP_SHELL_STATUS_CHANGED_CHANNEL',
    'removeListener:LINEUP_PLAYER_EVENT_CHANNEL',
    'removeListener:LINEUP_SHELL_STATUS_CHANGED_CHANNEL',
  ]);
});
