import test from 'node:test';
import assert from 'node:assert/strict';
import { ESLint } from 'eslint';

import {
  architectureRuleMessages,
  buildEslintArchitectureRules,
} from '../architecture-rules/buildEslintArchitectureRules.mjs';
import { desktopArchitectureRules } from '../architecture-rules/desktopArchitectureRules.mjs';

function getRestrictionFor(files) {
  return getEntryFor(files).rules['no-restricted-imports'][1].patterns[0];
}

function getEntryFor(files) {
  const config = buildEslintArchitectureRules(desktopArchitectureRules);
  const entry = config.find((candidate) => candidate.files?.includes(files));
  assert.ok(entry, `expected architecture rule for ${files}`);
  return entry;
}

function getRestrictionForEntry(files) {
  return getEntryFor(files).rules['no-restricted-imports']?.[1].patterns[0];
}

function getRestrictedPathsForEntry(files) {
  return getEntryFor(files).rules['no-restricted-imports']?.[1].paths ?? [];
}

function getRestrictedGlobalNames(files) {
  const entry = getEntryFor(files);
  return entry.rules['no-restricted-globals']
    .slice(1)
    .map((restriction) => restriction.name);
}

test('domain boundary blocks runtime imports', () => {
  const restriction = getRestrictionFor('src/domain/**/*.ts');

  assert.equal(restriction.message, architectureRuleMessages.domainBoundary);
  assert.ok(restriction.group.includes('electron'));
  assert.ok(restriction.group.includes('node:*'));
  assert.ok(restriction.group.includes('crypto'));
  assert.ok(restriction.group.includes('node:crypto'));
  assert.ok(restriction.group.includes('fs/promises'));
  assert.ok(restriction.group.includes('src/main'));
  assert.ok(restriction.group.includes('src/main/**'));
  assert.ok(restriction.group.includes('src/preload'));
  assert.ok(restriction.group.includes('src/preload/**'));
  assert.ok(restriction.group.includes('src/renderer'));
  assert.ok(restriction.group.includes('src/renderer/**'));
  assert.ok(restriction.group.includes('src/native-helper'));
  assert.ok(restriction.group.includes('src/native-helper/**'));
  assert.ok(restriction.group.includes('**/main'));
  assert.ok(restriction.group.includes('**/main/**'));
  assert.ok(restriction.group.includes('**/preload'));
  assert.ok(restriction.group.includes('**/preload/**'));
  assert.ok(restriction.group.includes('**/renderer'));
  assert.ok(restriction.group.includes('**/renderer/**'));
  assert.ok(restriction.group.includes('**/native-helper'));
  assert.ok(restriction.group.includes('**/native-helper/**'));
});

test('production boundary rules do not blanket-ignore tests', () => {
  const config = buildEslintArchitectureRules(desktopArchitectureRules);
  const productionEntries = [
    'src/domain/**/*.ts',
    'src/renderer/**/*.ts',
    'src/preload/**/*.cts',
    'src/main/**/*.ts',
    'src/native-helper/**/*.ts',
  ].map(getEntryFor);

  assert.equal(config.some((entry) => entry.ignores?.includes('src/**/__tests__/**')), false);
  for (const entry of productionEntries) {
    assert.equal(entry.ignores, undefined);
  }
});

test('domain boundary blocks browser and runtime globals', () => {
  const restrictedGlobals = getRestrictedGlobalNames('src/domain/**/*.ts');

  assert.deepEqual(
    restrictedGlobals,
    [
      'window',
      'document',
      'localStorage',
      'sessionStorage',
      'globalThis',
      'process',
      'Buffer',
      'require',
      'global',
      '__dirname',
      '__filename',
      'AbortController',
      'AbortSignal',
      'fetch',
      'setTimeout',
      'clearTimeout',
      'setInterval',
      'clearInterval',
      'URL',
      'URLSearchParams',
      'Headers',
      'Request',
      'Response',
      'WebSocket',
      'EventSource',
      'crypto',
      'navigator',
      'performance',
    ],
  );
});

test('ESLint rejects domain runtime imports and globals', async () => {
  const eslint = new ESLint({
    overrideConfigFile: true,
    overrideConfig: buildEslintArchitectureRules(desktopArchitectureRules),
  });
  const [result] = await eslint.lintText([
    "import crypto from 'node:crypto';",
    "import mainThing from '../../main/window';",
    "import mainRoot from '../../main';",
    "const rendererThing = await import('../../renderer/index');",
    "const rendererRoot = await import('../../renderer');",
    'const target = "electron";',
    'const computed = await import(target);',
    'const templated = await import(`node:fs/promises`);',
    'void crypto;',
    'void mainThing;',
    'void mainRoot;',
    'void rendererThing;',
    'void rendererRoot;',
    'void computed;',
    'void templated;',
    'void window;',
    'void localStorage;',
    'void process;',
    'void Buffer;',
    'void require;',
    'void __dirname;',
  ].join('\n'), { filePath: 'src/domain/channel/channelManager.ts' });

  assert.equal(
    result.messages.filter((message) => message.ruleId === 'no-restricted-imports').length,
    3,
  );
  assert.equal(
    result.messages.filter((message) => message.ruleId === 'no-restricted-syntax').length,
    5,
  );
  assert.equal(
    result.messages.filter((message) => message.ruleId === 'no-restricted-globals').length,
    6,
  );
});

test('ESLint rejects non-literal dynamic imports in runtime boundaries', async () => {
  const eslint = new ESLint({
    overrideConfigFile: true,
    overrideConfig: buildEslintArchitectureRules(desktopArchitectureRules),
  });
  const samples = [
    'src/renderer/View.ts',
    'src/preload/index.cts',
    'src/main/index.ts',
    'src/native-helper/host.ts',
  ];

  for (const filePath of samples) {
    const [result] = await eslint.lintText([
      'const target = "./dynamic";',
      'const loaded = await import(target);',
      'void loaded;',
    ].join('\n'), { filePath });

    assert.equal(
      result.messages.filter((message) => message.ruleId === 'no-restricted-syntax').length,
      1,
      `expected computed dynamic import rejection for ${filePath}`,
    );
  }
});

test('ESLint rejects domain globalThis runtime access', async () => {
  const eslint = new ESLint({
    overrideConfigFile: true,
    overrideConfig: buildEslintArchitectureRules(desktopArchitectureRules),
  });
  const [result] = await eslint.lintText([
    'const alias = globalThis;',
    'const key = "window";',
    'void alias;',
    'void globalThis.process;',
    "void globalThis['localStorage'];",
    'void globalThis[key];',
  ].join('\n'), { filePath: 'src/domain/scheduler/channelScheduler.ts' });

  assert.ok(
    result.messages.some((message) => message.ruleId === 'no-restricted-globals'),
    'expected direct globalThis use to be rejected',
  );
  assert.equal(
    result.messages.filter((message) => message.ruleId === 'no-restricted-syntax').length,
    3,
  );
});

test('renderer boundary blocks privileged imports', () => {
  const restriction = getRestrictionFor('src/renderer/**/*.ts');

  assert.equal(restriction.message, architectureRuleMessages.rendererBoundary);
  assert.ok(restriction.group.includes('electron'));
  assert.ok(restriction.group.includes('node:*'));
  assert.ok(restriction.group.includes('crypto'));
  assert.ok(restriction.group.includes('node:crypto'));
  assert.ok(restriction.group.includes('fs/promises'));
  assert.ok(restriction.group.includes('src/main/**'));
  assert.ok(restriction.group.includes('**/main/**'));
  assert.ok(restriction.group.includes('src/native-helper/**'));
});

test('renderer boundary blocks Node globals', () => {
  const restrictedGlobals = getRestrictedGlobalNames('src/renderer/**/*.ts');

  assert.ok(restrictedGlobals.includes('process'));
  assert.ok(restrictedGlobals.includes('Buffer'));
});

test('ESLint rejects renderer Node imports and nested main imports', async () => {
  const eslint = new ESLint({
    overrideConfigFile: true,
    overrideConfig: buildEslintArchitectureRules(desktopArchitectureRules),
  });
  const [result] = await eslint.lintText([
    "import crypto from 'crypto';",
    "import mainThing from '../../main/window';",
    'void crypto;',
    'void mainThing;',
  ].join('\n'), { filePath: 'src/renderer/deep/View.ts' });

  const restrictedMessages = result.messages.filter((message) => message.ruleId === 'no-restricted-imports');
  assert.equal(restrictedMessages.length, 2);
});

test('ESLint rejects renderer dynamic imports across privileged boundaries', async () => {
  const eslint = new ESLint({
    overrideConfigFile: true,
    overrideConfig: buildEslintArchitectureRules(desktopArchitectureRules),
  });
  const [result] = await eslint.lintText([
    "const crypto = await import('crypto');",
    "const nodeCrypto = await import('node:crypto');",
    "const nodeFs = await import('node:fs/promises');",
    "const electron = await import('electron');",
    "const mainThing = await import('../../main/window');",
    'void crypto;',
    'void nodeCrypto;',
    'void nodeFs;',
    'void electron;',
    'void mainThing;',
  ].join('\n'), { filePath: 'src/renderer/deep/View.ts' });

  const restrictedMessages = result.messages.filter((message) => message.ruleId === 'no-restricted-syntax');
  assert.equal(restrictedMessages.length, 5);
});

test('preload boundary cannot import renderer or native helper implementation', () => {
  const restriction = getRestrictionFor('src/preload/**/*.cts');

  assert.equal(restriction.message, architectureRuleMessages.preloadBoundary);
  assert.ok(restriction.group.includes('src/renderer/**'));
  assert.ok(restriction.group.includes('src/native-helper/**'));
});

test('main and native helper boundaries do not depend on renderer implementation', () => {
  const mainRestriction = getRestrictionFor('src/main/**/*.ts');
  const helperRestriction = getRestrictionFor('src/native-helper/**/*.ts');

  assert.equal(mainRestriction.message, architectureRuleMessages.mainBoundary);
  assert.equal(helperRestriction.message, architectureRuleMessages.nativeHelperBoundary);
  assert.ok(mainRestriction.group.includes('src/renderer/**'));
  assert.ok(helperRestriction.group.includes('src/renderer/**'));
});

test('test owner rules are generated from owner data', () => {
  const contractsRestriction = getRestrictionForEntry('src/__tests__/contracts/**/*.test.ts');
  const domainRestriction = getRestrictionForEntry('src/__tests__/domain/**/*.test.ts');
  const mainRestriction = getRestrictionForEntry('src/__tests__/main/**/*.test.ts');
  const rendererRestriction = getRestrictionForEntry('src/__tests__/renderer/**/*.test.ts');
  const domainPaths = getRestrictedPathsForEntry('src/__tests__/domain/**/*.test.ts');

  assert.ok(contractsRestriction.group.includes('**/main/**'));
  assert.ok(contractsRestriction.group.includes('**/main'));
  assert.ok(contractsRestriction.group.includes('node:fs'));
  assert.equal(contractsRestriction.group.includes('node:test'), false);
  assert.equal(contractsRestriction.group.includes('node:assert/strict'), false);

  assert.ok(domainRestriction.group.includes('**/main/**'));
  assert.ok(domainRestriction.group.includes('**/main'));
  assert.ok(domainRestriction.group.includes('**/contracts/**'));
  assert.ok(domainRestriction.group.includes('**/contracts'));
  assert.ok(domainPaths.some((restriction) => restriction.name === 'domain'));
  assert.ok(domainRestriction.group.includes('node:fs/promises'));
  assert.equal(domainRestriction.group.includes('node:test'), false);
  assert.equal(domainRestriction.group.includes('node:assert'), false);

  assert.ok(mainRestriction.group.includes('**/renderer/**'));
  assert.ok(mainRestriction.group.includes('**/preload'));
  assert.equal(mainRestriction.group.includes('node:fs/promises'), false);
  assert.ok(rendererRestriction.group.includes('**/preload/**'));
  assert.ok(rendererRestriction.group.includes('**/preload'));
  assert.ok(rendererRestriction.group.includes('node:process'));
});

test('ESLint enforces owner test import boundaries', async () => {
  const eslint = new ESLint({
    overrideConfigFile: true,
    overrideConfig: buildEslintArchitectureRules(desktopArchitectureRules),
  });

  const [domainAllowed] = await eslint.lintText([
    "import test from 'node:test';",
    "import assert from 'node:assert/strict';",
    "import { ChannelManager } from '../../domain/channel/channelManager.js';",
    'void test;',
    'void assert;',
    'void ChannelManager;',
  ].join('\n'), { filePath: 'src/__tests__/domain/channelDomain.test.ts' });
  assert.equal(domainAllowed.messages.length, 0);

  const [domainForbidden] = await eslint.lintText([
    "import fs from 'node:fs/promises';",
    "import { DesktopPersistenceStore } from '../../main/persistence/desktopPersistenceStore.js';",
    'void fs;',
    'void DesktopPersistenceStore;',
  ].join('\n'), { filePath: 'src/__tests__/domain/channelPersistence.test.ts' });
  assert.equal(
    domainForbidden.messages.filter((message) => message.ruleId === 'no-restricted-imports').length,
    2,
  );

  const [mainAllowed] = await eslint.lintText([
    "import fs from 'node:fs/promises';",
    "import { ChannelPersistenceStore } from '../../domain/channel/channelPersistenceStore.js';",
    "import { DesktopChannelPersistenceStore } from '../../main/persistence/desktopChannelPersistenceStore.js';",
    'void fs;',
    'void ChannelPersistenceStore;',
    'void DesktopChannelPersistenceStore;',
  ].join('\n'), { filePath: 'src/__tests__/main/channelPersistenceAdapter.test.ts' });
  assert.equal(mainAllowed.messages.length, 0);

  const [mainForbidden] = await eslint.lintText([
    "import preloadEntry from '../../preload/index.cjs';",
    'void preloadEntry;',
  ].join('\n'), { filePath: 'src/__tests__/main/shellSecurity.test.ts' });
  assert.equal(
    mainForbidden.messages.filter((message) => message.ruleId === 'no-restricted-imports').length,
    1,
  );
});

test('ESLint rejects owner test root imports and dynamic forbidden imports', async () => {
  const eslint = new ESLint({
    overrideConfigFile: true,
    overrideConfig: buildEslintArchitectureRules(desktopArchitectureRules),
  });

  const [domainRootImport] = await eslint.lintText([
    "import mainRoot from '../../main';",
    'void mainRoot;',
  ].join('\n'), { filePath: 'src/__tests__/domain/channelPersistence.test.ts' });
  assert.equal(
    domainRootImport.messages.filter((message) => message.ruleId === 'no-restricted-imports').length,
    1,
  );

  const [domainDynamicImport] = await eslint.lintText([
    "const store = await import('../../main/persistence/desktopPersistenceStore.js');",
    'void store;',
  ].join('\n'), { filePath: 'src/__tests__/domain/channelPersistence.test.ts' });
  assert.equal(
    domainDynamicImport.messages.filter((message) => message.ruleId === 'no-restricted-syntax').length,
    1,
  );

  const [domainComputedDynamicImport] = await eslint.lintText([
    "const spec = '../../main/persistence/desktopPersistenceStore.js';",
    'const store = await import(spec);',
    'void store;',
  ].join('\n'), { filePath: 'src/__tests__/domain/channelPersistence.test.ts' });
  assert.equal(
    domainComputedDynamicImport.messages.filter((message) => message.ruleId === 'no-restricted-syntax').length,
    1,
  );

  const [domainBuiltinImport] = await eslint.lintText([
    "import domain from 'domain';",
    'void domain;',
  ].join('\n'), { filePath: 'src/__tests__/domain/channelPersistence.test.ts' });
  assert.equal(
    domainBuiltinImport.messages.filter((message) => message.ruleId === 'no-restricted-imports').length,
    1,
  );

  const [domainDynamicBuiltinImport] = await eslint.lintText([
    "const domain = await import('domain');",
    'void domain;',
  ].join('\n'), { filePath: 'src/__tests__/domain/channelPersistence.test.ts' });
  assert.equal(
    domainDynamicBuiltinImport.messages.filter((message) => message.ruleId === 'no-restricted-syntax').length,
    1,
  );

  const [mainRootImport] = await eslint.lintText([
    "import preloadRoot from '../../preload';",
    'void preloadRoot;',
  ].join('\n'), { filePath: 'src/__tests__/main/shellSecurity.test.ts' });
  assert.equal(
    mainRootImport.messages.filter((message) => message.ruleId === 'no-restricted-imports').length,
    1,
  );

  const [rendererDynamicNodeImport] = await eslint.lintText([
    "const fs = await import('node:fs/promises');",
    'void fs;',
  ].join('\n'), { filePath: 'src/__tests__/renderer/appView.test.ts' });
  assert.equal(
    rendererDynamicNodeImport.messages.filter((message) => message.ruleId === 'no-restricted-syntax').length,
    1,
  );

  const [rendererComputedDynamicNodeImport] = await eslint.lintText([
    "const spec = 'node:fs/promises';",
    'const fs = await import(spec);',
    'void fs;',
  ].join('\n'), { filePath: 'src/__tests__/renderer/appView.test.ts' });
  assert.equal(
    rendererComputedDynamicNodeImport.messages.filter((message) => message.ruleId === 'no-restricted-syntax').length,
    1,
  );

  const [rendererBuiltinImport] = await eslint.lintText([
    "import domain from 'domain';",
    'void domain;',
  ].join('\n'), { filePath: 'src/__tests__/renderer/appView.test.ts' });
  assert.equal(
    rendererBuiltinImport.messages.filter((message) => message.ruleId === 'no-restricted-imports').length,
    1,
  );

  const [rendererDynamicBuiltinImport] = await eslint.lintText([
    "const domain = await import('domain');",
    'void domain;',
  ].join('\n'), { filePath: 'src/__tests__/renderer/appView.test.ts' });
  assert.ok(
    rendererDynamicBuiltinImport.messages.some((message) => message.ruleId === 'no-restricted-syntax'),
    'expected bare domain dynamic import to be rejected in renderer tests',
  );
});

test('integration seam rules are limited to declared proof test paths', async () => {
  const eslint = new ESLint({
    overrideConfigFile: true,
    overrideConfig: buildEslintArchitectureRules(desktopArchitectureRules),
  });
  const integrationOwnerEntry = getEntryFor('src/__tests__/integration/**/*.test.ts');
  const seamEntry = getEntryFor('src/__tests__/integration/preloadContractVocabulary.test.ts');

  assert.deepEqual(integrationOwnerEntry.ignores, [
    'src/__tests__/integration/preloadContractVocabulary.test.ts',
  ]);
  assert.ok(seamEntry.rules['no-restricted-syntax']);

  const [allowed] = await eslint.lintText([
    "import test from 'node:test';",
    "import assert from 'node:assert/strict';",
    "import { readFileSync } from 'node:fs';",
    "import ts from 'typescript';",
    "import { PLAYER_RENDERER_INTENTS } from '../../contracts/ipc.js';",
    'void test;',
    'void assert;',
    'void readFileSync;',
    'void ts;',
    'void PLAYER_RENDERER_INTENTS;',
  ].join('\n'), { filePath: 'src/__tests__/integration/preloadContractVocabulary.test.ts' });
  assert.equal(allowed.messages.length, 0);

  const [forbiddenMain] = await eslint.lintText([
    "import { isAllowedShellUrl } from '../../main/shellSecurity.js';",
    'void isAllowedShellUrl;',
  ].join('\n'), { filePath: 'src/__tests__/integration/preloadContractVocabulary.test.ts' });
  assert.equal(
    forbiddenMain.messages.filter((message) => message.ruleId === 'no-restricted-syntax').length,
    1,
  );

  const [forbiddenPreload] = await eslint.lintText([
    "import '../preload/index.cts';",
  ].join('\n'), { filePath: 'src/__tests__/integration/preloadContractVocabulary.test.ts' });
  assert.equal(
    forbiddenPreload.messages.filter((message) => message.ruleId === 'no-restricted-syntax').length,
    1,
  );

  const [unapprovedIntegrationPath] = await eslint.lintText([
    "import { isAllowedShellUrl } from '../../main/shellSecurity.js';",
    'void isAllowedShellUrl;',
  ].join('\n'), { filePath: 'src/__tests__/integration/channelPersistence.test.ts' });
  assert.equal(
    unapprovedIntegrationPath.messages.filter((message) => message.ruleId === 'no-restricted-syntax').length,
    1,
  );
});
