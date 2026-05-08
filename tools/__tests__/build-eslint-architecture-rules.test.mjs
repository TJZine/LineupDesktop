import test from 'node:test';
import assert from 'node:assert/strict';
import { ESLint } from 'eslint';

import {
  architectureRuleMessages,
  buildEslintArchitectureRules,
} from '../architecture-rules/buildEslintArchitectureRules.mjs';
import { desktopArchitectureRules } from '../architecture-rules/desktopArchitectureRules.mjs';

function getRestrictionFor(files) {
  const config = buildEslintArchitectureRules(desktopArchitectureRules);
  const entry = config.find((candidate) => candidate.files?.includes(files));
  assert.ok(entry, `expected architecture rule for ${files}`);
  return entry.rules['no-restricted-imports'][1].patterns[0];
}

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
  const config = buildEslintArchitectureRules(desktopArchitectureRules);
  const entry = config.find((candidate) => candidate.files?.includes('src/renderer/**/*.ts'));
  const restrictedGlobals = entry.rules['no-restricted-globals'];

  assert.ok(restrictedGlobals.some((restriction) => restriction.name === 'process'));
  assert.ok(restrictedGlobals.some((restriction) => restriction.name === 'Buffer'));
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
