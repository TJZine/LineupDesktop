import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import ts from 'typescript';

import {
  LINEUP_PLAYER_CLEANUP_CHANNEL,
  LINEUP_PLAYER_COMMAND_CHANNEL,
  LINEUP_PLAYER_EVENT_CHANNEL,
  LINEUP_PLAYER_GET_SNAPSHOT_CHANNEL,
  LINEUP_PLEX_CANCEL_PIN_CHANNEL,
  LINEUP_PLEX_GET_HOME_USERS_CHANNEL,
  LINEUP_PLEX_GET_METADATA_CHANNEL,
  LINEUP_PLEX_GET_SNAPSHOT_CHANNEL,
  LINEUP_PLEX_LIST_LIBRARY_ITEMS_CHANNEL,
  LINEUP_PLEX_LIST_LIBRARY_SECTIONS_CHANNEL,
  LINEUP_PLEX_POLL_PIN_CHANNEL,
  LINEUP_PLEX_REFRESH_SERVERS_CHANNEL,
  LINEUP_PLEX_REQUEST_PIN_CHANNEL,
  LINEUP_PLEX_RESTORE_SELECTED_SERVER_CHANNEL,
  LINEUP_PLEX_SEARCH_LIBRARY_CHANNEL,
  LINEUP_PLEX_SELECT_SERVER_CHANNEL,
  LINEUP_PLEX_SWITCH_HOME_USER_CHANNEL,
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
import {
  PLEX_FORBIDDEN_RENDERER_FIELD_KEYS,
  PLEX_RUNTIME_ERROR_CODES,
  PLEX_RUNTIME_OPERATIONS,
} from '../../contracts/plex.js';
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

type PreloadInvokeCall = {
  channel: string;
  request: { requestId: string; payload: unknown };
};

function createPreloadHarness(
  invoke: (
    channel: string,
    request: unknown,
    input: (value: unknown) => unknown,
  ) => unknown | Promise<unknown>,
): {
  api: Record<string, { [method: string]: (...args: unknown[]) => Promise<unknown> }>;
  calls: PreloadInvokeCall[];
  input: (value: unknown) => unknown;
} {
  const calls: PreloadInvokeCall[] = [];
  let exposedApi: unknown = null;
  const input = (value: unknown) => JSON.parse(JSON.stringify(value)) as unknown;
  const compiled = ts.transpileModule(preloadSourceText, {
    compilerOptions: {
      module: ts.ModuleKind.CommonJS,
      target: ts.ScriptTarget.ES2022,
    },
    fileName: 'src/preload/index.cts',
  }).outputText;
  const requireElectron = (moduleName: string) => {
    assert.equal(moduleName, 'electron');
    return {
      contextBridge: {
        exposeInMainWorld: (key: string, value: unknown) => {
          assert.equal(key, 'lineupDesktop');
          exposedApi = value;
        },
      },
      ipcRenderer: {
        invoke: async (channel: string, request: unknown) => {
          assert.ok(isPlexInvokeRequest(request));
          calls.push({ channel, request });
          return invoke(channel, request, input);
        },
        on: () => undefined,
        removeListener: () => undefined,
      },
    };
  };
  const exportsObject = {};
  const evaluatePreload = new Function('require', 'exports', compiled);
  evaluatePreload(requireElectron, exportsObject);
  assert.ok(exposedApi !== null && typeof exposedApi === 'object');
  return {
    api: exposedApi as Record<string, { [method: string]: (...args: unknown[]) => Promise<unknown> }>,
    calls,
    input,
  };
}

function isPlexInvokeRequest(value: unknown): value is { requestId: string; payload: unknown } {
  return (
    typeof value === 'object' &&
    value !== null &&
    'requestId' in value &&
    typeof value.requestId === 'string' &&
    'payload' in value
  );
}

function createSafePlexSnapshot(): Record<string, unknown> {
  return {
    auth: {
      state: 'signed-in',
      pin: { id: 42, code: 'ABCD', expiresAtMs: 2, claimed: false },
      profile: { accountId: 'account-1', displayName: 'Profile' },
      homeUsers: [{ id: 'home-1', title: 'Profile', admin: false, protected: true }],
      credentialStatus: 'present',
    },
    servers: {
      status: 'ready',
      selected: null,
      items: [],
      lastSelection: null,
    },
    library: {
      status: 'ready',
      sections: [],
      selectedSectionId: null,
      items: [],
      search: null,
      metadata: null,
    },
    lastError: null,
    updatedAtMs: 3,
  };
}

function createSafePlexFailure(
  operation: string,
  requestId: string,
  code = 'PLEX_AUTH_REQUIRED',
): Record<string, unknown> {
  return {
    ok: false,
    requestId,
    error: {
      code,
      message: 'Plex request failed.',
      retryable: false,
      recoverable: true,
      operation,
    },
  };
}

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
  LINEUP_PLEX_GET_SNAPSHOT_CHANNEL,
  LINEUP_PLEX_REQUEST_PIN_CHANNEL,
  LINEUP_PLEX_POLL_PIN_CHANNEL,
  LINEUP_PLEX_CANCEL_PIN_CHANNEL,
  LINEUP_PLEX_GET_HOME_USERS_CHANNEL,
  LINEUP_PLEX_SWITCH_HOME_USER_CHANNEL,
  LINEUP_PLEX_RESTORE_SELECTED_SERVER_CHANNEL,
  LINEUP_PLEX_REFRESH_SERVERS_CHANNEL,
  LINEUP_PLEX_SELECT_SERVER_CHANNEL,
  LINEUP_PLEX_LIST_LIBRARY_SECTIONS_CHANNEL,
  LINEUP_PLEX_LIST_LIBRARY_ITEMS_CHANNEL,
  LINEUP_PLEX_SEARCH_LIBRARY_CHANNEL,
  LINEUP_PLEX_GET_METADATA_CHANNEL,
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
    'LINEUP_PLEX_GET_SNAPSHOT_CHANNEL',
    'LINEUP_PLEX_REQUEST_PIN_CHANNEL',
    'LINEUP_PLEX_POLL_PIN_CHANNEL',
    'LINEUP_PLEX_CANCEL_PIN_CHANNEL',
    'LINEUP_PLEX_GET_HOME_USERS_CHANNEL',
    'LINEUP_PLEX_SWITCH_HOME_USER_CHANNEL',
    'LINEUP_PLEX_RESTORE_SELECTED_SERVER_CHANNEL',
    'LINEUP_PLEX_REFRESH_SERVERS_CHANNEL',
    'LINEUP_PLEX_SELECT_SERVER_CHANNEL',
    'LINEUP_PLEX_LIST_LIBRARY_SECTIONS_CHANNEL',
    'LINEUP_PLEX_LIST_LIBRARY_ITEMS_CHANNEL',
    'LINEUP_PLEX_SEARCH_LIBRARY_CHANNEL',
    'LINEUP_PLEX_GET_METADATA_CHANNEL',
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
  return expression.elements.flatMap((element) => {
    if (ts.isSpreadElement(element) && ts.isIdentifier(element.expression)) {
      const declaration = findPreloadVariableDeclaration(element.expression.text);
      assert.ok(declaration?.initializer, `expected ${name} spread ${element.expression.text} in preload entrypoint`);
      return readStringArrayInitializer(element.expression.text, declaration.initializer);
    }
    assert.ok(ts.isStringLiteral(element), `expected ${name} to contain only string literals or const spreads`);
    return [element.text];
  });
}

function readStringConstInitializer(name: string, initializer: ts.Expression): string {
  const expression = unwrapExpression(initializer);
  assert.ok(ts.isStringLiteral(expression), `expected ${name} to be a string literal`);
  return expression.text;
}

function readRegExpConstInitializer(name: string): { pattern: string; flags: string } {
  const declaration = findPreloadVariableDeclaration(name);
  assert.ok(declaration?.initializer, `expected ${name} in preload entrypoint`);
  const expression = unwrapExpression(declaration.initializer);
  assert.ok(ts.isRegularExpressionLiteral(expression), `expected ${name} to be a RegExp literal`);
  const match = /^\/(.*)\/([a-z]*)$/su.exec(expression.text);
  assert.ok(match, `expected ${name} to have a parseable RegExp literal`);
  return { pattern: match[1], flags: match[2] };
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

function isInvokePlexChannelParameter(node: ts.Identifier): boolean {
  if (node.text !== 'channel') {
    return false;
  }
  let current: ts.Node | undefined = node;
  while (current !== undefined && !ts.isSourceFile(current)) {
    if (
      ts.isFunctionDeclaration(current) &&
      current.name?.text === 'invokePlex' &&
      current.parameters.some((parameter) => ts.isIdentifier(parameter.name) && parameter.name.text === 'channel')
    ) {
      return true;
    }
    current = current.parent;
  }
  return false;
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

function collectInvokePlexChannelArguments(): string[] {
  const channels: string[] = [];

  function visit(node: ts.Node): void {
    if (
      ts.isCallExpression(node) &&
      ts.isIdentifier(node.expression) &&
      node.expression.text === 'invokePlex'
    ) {
      const [channelExpression] = node.arguments;
      assert.ok(channelExpression, 'invokePlex must pass a channel');
      assert.ok(ts.isIdentifier(channelExpression), 'invokePlex channel must be a constant');
      assertApprovedChannelIdentifier(channelExpression.text);
      channels.push(channelExpression.text);
    }
    ts.forEachChild(node, visit);
  }

  visit(preloadSourceFile);
  return channels;
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
  assert.deepEqual(readRegExpConstInitializer('DIAGNOSTICS_REQUEST_ID_PATTERN'), {
    pattern: DIAGNOSTICS_REQUEST_ID_PATTERN_SOURCE,
    flags: 'u',
  });
  assert.deepEqual(readRegExpConstInitializer('PLEX_REQUEST_ID_PATTERN'), {
    pattern: '^[A-Za-z0-9._-]{1,120}$',
    flags: 'u',
  });
  assert.deepEqual(readRegExpConstInitializer('DIAGNOSTICS_UNSAFE_RENDERER_CONTEXT_VALUE_PATTERN'), {
    pattern: DIAGNOSTICS_UNSAFE_RENDERER_CONTEXT_VALUE_PATTERN_SOURCE,
    flags: 'iu',
  });
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
  assert.deepEqual(readPreloadStringArrayConst('PLEX_RUNTIME_OPERATIONS'), [
    ...PLEX_RUNTIME_OPERATIONS,
  ]);
  assert.deepEqual(readPreloadStringArrayConst('PLEX_RUNTIME_ERROR_CODES'), [
    ...PLEX_RUNTIME_ERROR_CODES,
  ]);
  const preloadPlexForbiddenKeys = readPreloadStringArrayConst('PLEX_FORBIDDEN_RENDERER_FIELD_KEYS');
  assert.deepEqual(
    [...new Set(preloadPlexForbiddenKeys)].sort(),
    [...new Set(PLEX_FORBIDDEN_RENDERER_FIELD_KEYS)].sort(),
  );
  assert.equal(preloadPlexForbiddenKeys.length, new Set(preloadPlexForbiddenKeys).size);
});

test('preload Plex bridge validates invoke results before returning them', async () => {
  const snapshot = createSafePlexSnapshot();
  const harness = createPreloadHarness((_channel, request, input) => {
    assert.ok(isPlexInvokeRequest(request));
    return input({
      ok: true,
      requestId: request.requestId,
      value: {
        sectionId: '1',
        offset: 0,
        limit: 25,
        items: [],
        snapshot,
      },
    });
  });

  const result = await harness.api.plex.listLibraryItems(harness.input({
    sectionId: '1',
    offset: 0.9,
    limit: 25,
  }));

  assert.equal(harness.calls.length, 1);
  assert.deepEqual(JSON.parse(JSON.stringify(harness.calls[0]?.request.payload)), {
    sectionId: '1',
    offset: 0,
    limit: 25,
  });
  assert.equal((result as { ok: boolean }).ok, true);
});

test('preload Plex bridge converts malformed or privileged invoke results to local validation failures', async () => {
  const privileged = createPreloadHarness((_channel, request, input) => {
    assert.ok(isPlexInvokeRequest(request));
    return input({
      ok: true,
      requestId: request.requestId,
      value: { snapshot: createSafePlexSnapshot(), accessToken: 'private' },
    });
  });
  const privilegedResult = await privileged.api.plex.getSnapshot();

  assert.equal((privilegedResult as { ok: boolean }).ok, false);
  assert.equal(
    (privilegedResult as { error: { code: string } }).error.code,
    'PLEX_VALIDATION_FAILED',
  );

  const malformedCancelled = createPreloadHarness((_channel, request, input) => {
    assert.ok(isPlexInvokeRequest(request));
    return input({
      ...createSafePlexFailure('pollPin', request.requestId, 'PLEX_CANCELLED'),
      cancelled: false,
    });
  });
  const malformedCancelledResult = await malformedCancelled.api.plex.pollPin(
    malformedCancelled.input({ pinId: 42 }),
  );

  assert.equal((malformedCancelledResult as { ok: boolean }).ok, false);
  assert.equal(
    (malformedCancelledResult as { error: { code: string } }).error.code,
    'PLEX_VALIDATION_FAILED',
  );
});

test('preload Plex bridge converts invoke rejections to local validation failures', async () => {
  const harness = createPreloadHarness(() => {
    throw new Error('raw token serverUri failure');
  });

  const result = await harness.api.plex.getSnapshot();

  assert.equal((result as { ok: boolean }).ok, false);
  assert.equal((result as { requestId: string }).requestId, harness.calls[0]?.request.requestId);
  assert.equal(
    (result as { error: { code: string } }).error.code,
    'PLEX_VALIDATION_FAILED',
  );
  assert.equal(
    (result as { error: { message: string; operation: string } }).error.message,
    'Plex invoke failed (Error).',
  );
  assert.equal(
    (result as { error: { message: string; operation: string } }).error.operation,
    'getSnapshot',
  );
  assert.doesNotMatch(JSON.stringify(result), /raw token|serverUri/u);
});

test('preload Plex bridge rejects mismatched success request ids locally', async () => {
  const harness = createPreloadHarness((_channel, request, input) => {
    assert.ok(isPlexInvokeRequest(request));
    return input({
      ok: true,
      requestId: `${request.requestId}-mismatch`,
      value: createSafePlexSnapshot(),
    });
  });

  const result = await harness.api.plex.getSnapshot();

  assert.equal((result as { ok: boolean }).ok, false);
  assert.equal(
    (result as { error: { code: string } }).error.code,
    'PLEX_VALIDATION_FAILED',
  );
  assert.equal((result as { requestId: string }).requestId, harness.calls[0]?.request.requestId);
});

test('preload Plex bridge rejects mismatched failure request ids locally', async () => {
  const harness = createPreloadHarness((_channel, request, input) => {
    assert.ok(isPlexInvokeRequest(request));
    return input(createSafePlexFailure('pollPin', `${request.requestId}-mismatch`));
  });

  const result = await harness.api.plex.pollPin(harness.input({ pinId: 42 }));

  assert.equal((result as { ok: boolean }).ok, false);
  assert.equal(
    (result as { error: { code: string } }).error.code,
    'PLEX_VALIDATION_FAILED',
  );
  assert.equal((result as { requestId: string }).requestId, harness.calls[0]?.request.requestId);
});

test('preload Plex bridge rejects invalid pin ids and limits without IPC', async () => {
  const harness = createPreloadHarness(() => {
    assert.fail('invalid Plex renderer input must not invoke IPC');
  });

  for (const input of [{ pinId: 1.5 }, { pinId: Number.NaN }, { pinId: 0 }]) {
    const result = await harness.api.plex.pollPin(harness.input(input));
    assert.equal((result as { ok: boolean }).ok, false);
    assert.equal(
      (result as { error: { code: string } }).error.code,
      'PLEX_VALIDATION_FAILED',
    );
  }

  for (const input of [
    { sectionId: '1', limit: 1.5 },
    { sectionId: '1', limit: 0 },
    { sectionId: '1', limit: 5001 },
    { sectionId: '', limit: 25 },
    { sectionId: 42, limit: 25 },
    { sectionId: null, limit: 25 },
    { sectionId: 'x'.repeat(257), limit: 25 },
  ]) {
    const result = await harness.api.plex.listLibraryItems(harness.input(input));
    assert.equal((result as { ok: boolean }).ok, false);
    assert.equal(
      (result as { error: { code: string } }).error.code,
      'PLEX_VALIDATION_FAILED',
    );
  }

  assert.equal(harness.calls.length, 0);
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

      if (isInvokePlexChannelParameter(channelExpression)) {
        observedCalls.push(`${methodName}:invokePlex.channel`);
        ts.forEachChild(node, visit);
        return;
      }

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
    'invoke:invokePlex.channel',
    'on:LINEUP_PLAYER_EVENT_CHANNEL',
    'on:LINEUP_SHELL_STATUS_CHANGED_CHANNEL',
    'removeListener:LINEUP_PLAYER_EVENT_CHANNEL',
    'removeListener:LINEUP_SHELL_STATUS_CHANGED_CHANNEL',
  ]);
  assert.deepEqual(collectInvokePlexChannelArguments().sort(), [
    'LINEUP_PLEX_CANCEL_PIN_CHANNEL',
    'LINEUP_PLEX_GET_HOME_USERS_CHANNEL',
    'LINEUP_PLEX_GET_METADATA_CHANNEL',
    'LINEUP_PLEX_GET_SNAPSHOT_CHANNEL',
    'LINEUP_PLEX_LIST_LIBRARY_ITEMS_CHANNEL',
    'LINEUP_PLEX_LIST_LIBRARY_SECTIONS_CHANNEL',
    'LINEUP_PLEX_POLL_PIN_CHANNEL',
    'LINEUP_PLEX_REFRESH_SERVERS_CHANNEL',
    'LINEUP_PLEX_REQUEST_PIN_CHANNEL',
    'LINEUP_PLEX_RESTORE_SELECTED_SERVER_CHANNEL',
    'LINEUP_PLEX_SEARCH_LIBRARY_CHANNEL',
    'LINEUP_PLEX_SELECT_SERVER_CHANNEL',
    'LINEUP_PLEX_SWITCH_HOME_USER_CHANNEL',
  ]);
});
