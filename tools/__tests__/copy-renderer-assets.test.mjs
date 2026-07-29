import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

import {
  copyRendererAssets,
  copyRendererChannelBuilderRuntime,
  copyRendererSettingsRuntime,
} from '../copy-renderer-assets.mjs';

test('renderer asset copy preserves recursive files and exact binary hashes', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'lineup-renderer-assets-'));
  const source = path.join(root, 'source');
  const target = path.join(root, 'target');
  try {
    fs.mkdirSync(path.join(source, 'styles'), { recursive: true });
    fs.mkdirSync(path.join(source, 'assets', 'nested'), { recursive: true });
    fs.writeFileSync(path.join(source, 'index.html'), '<!doctype html>');
    fs.writeFileSync(path.join(source, 'styles.css'), '@import "./styles/base.css";');
    fs.writeFileSync(path.join(source, 'styles', 'base.css'), ':root{}');
    fs.writeFileSync(path.join(source, 'assets', 'lineup-logo-mark.png'), new Uint8Array([0, 1, 2, 3]));
    fs.writeFileSync(path.join(source, 'assets', 'nested', 'proof.bin'), new Uint8Array([9, 8, 7, 6]));

    copyRendererAssets(source, target);

    for (const relativePath of [
      'index.html',
      'styles.css',
      path.join('styles', 'base.css'),
      path.join('assets', 'lineup-logo-mark.png'),
      path.join('assets', 'nested', 'proof.bin'),
    ]) {
      const sourceHash = sha256(path.join(source, relativePath));
      const targetHash = sha256(path.join(target, relativePath));
      assert.equal(targetHash, sourceHash, relativePath);
    }
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

test('renderer settings runtime copy resets and stages the exact compiled dependency closure', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'lineup-renderer-settings-runtime-'));
  const compiled = path.join(root, 'dist', 'contracts');
  const renderer = path.join(root, 'dist', 'renderer');
  try {
    fs.mkdirSync(path.join(compiled, 'nested'), { recursive: true });
    fs.writeFileSync(
      path.join(compiled, 'settings.js'),
      "import './settingsAudioValidation.js';\nexport const settings = true;\n",
    );
    fs.writeFileSync(
      path.join(compiled, 'settingsAudioValidation.js'),
      'export const validation = true;\n',
    );
    fs.writeFileSync(path.join(compiled, 'settings.js.map'), new Uint8Array([1]));
    fs.writeFileSync(path.join(compiled, 'shell.js'), new Uint8Array([2]));
    fs.writeFileSync(path.join(compiled, 'nested', 'other.js'), new Uint8Array([3]));
    fs.mkdirSync(path.join(renderer, 'contracts'), { recursive: true });
    fs.writeFileSync(path.join(renderer, 'contracts', 'obsolete.js'), 'stale');

    copyRendererSettingsRuntime(compiled, renderer);

    const servedContracts = path.join(renderer, 'contracts');
    const servedSettings = path.join(servedContracts, 'settings.js');
    assert.equal(sha256(servedSettings), sha256(path.join(compiled, 'settings.js')));
    assert.equal(
      sha256(path.join(servedContracts, 'settingsAudioValidation.js')),
      sha256(path.join(compiled, 'settingsAudioValidation.js')),
    );
    assert.deepEqual(fs.readdirSync(renderer), ['contracts']);
    assert.deepEqual(
      fs.readdirSync(servedContracts).sort(),
      ['settings.js', 'settingsAudioValidation.js'],
    );
    for (const relativePath of [
      'obsolete.js',
      'settings.js.map',
      'shell.js',
      path.join('nested', 'other.js'),
    ]) {
      assert.equal(fs.existsSync(path.join(servedContracts, relativePath)), false, relativePath);
    }
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
  assert.equal(fs.existsSync(root), false);
});

test('renderer runtime copy includes the byte-exact relative dependency closure for config', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'lineup-renderer-runtime-'));
  const compiled = path.join(root, 'dist', 'domain', 'channelBuilder');
  const renderer = path.join(root, 'dist', 'renderer');
  try {
    fs.mkdirSync(compiled, { recursive: true });
    for (const [fileName, source] of [
      [
        'config.js',
        "import './constants.js';\nexport { exact } from './exactRecord.js';\nvoid import('./lazy.js');\n",
      ],
      ['constants.js', 'export const maximum = 500;\n'],
      ['exactRecord.js', "import { helper } from './recordHelper.js';\nexport const exact = helper;\n"],
      ['recordHelper.js', 'export const helper = true;\n'],
      ['lazy.js', 'export const lazy = true;\n'],
      ['config.js.map', new Uint8Array([9])],
      ['index.js', new Uint8Array([10])],
      ['planner.js', new Uint8Array([11])],
    ]) {
      fs.writeFileSync(path.join(compiled, fileName), source);
    }

    copyRendererChannelBuilderRuntime(compiled, renderer);

    const served = path.join(renderer, 'domain', 'channelBuilder');
    for (const fileName of [
      'config.js',
      'constants.js',
      'exactRecord.js',
      'lazy.js',
      'recordHelper.js',
    ]) {
      assert.equal(
        sha256(path.join(served, fileName)),
        sha256(path.join(compiled, fileName)),
        fileName,
      );
    }
    for (const fileName of ['config.js.map', 'index.js', 'planner.js']) {
      assert.equal(fs.existsSync(path.join(served, fileName)), false, fileName);
    }
    assert.deepEqual(fs.readdirSync(served).sort(), [
      'config.js',
      'constants.js',
      'exactRecord.js',
      'lazy.js',
      'recordHelper.js',
    ]);
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

test('renderer runtime copy ignores comments, strings, import.meta, and nonliteral dynamic imports', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'lineup-renderer-runtime-syntax-'));
  const compiled = path.join(root, 'dist', 'domain', 'channelBuilder');
  const renderer = path.join(root, 'dist', 'renderer');
  try {
    fs.mkdirSync(compiled, { recursive: true });
    fs.writeFileSync(
      path.join(compiled, 'config.js'),
      [
        "// import './commented-line.js';",
        "/* export { noise } from './commented-block.js'; */",
        "const sourceText = \"import './string-noise.js';\";",
        'const moduleUrl = import.meta.url;',
        "const computedSpecifier = './computed.js';",
        'void import(computedSpecifier);',
        'export { moduleUrl, sourceText };',
      ].join('\n'),
    );
    for (const fileName of [
      'commented-line.js',
      'commented-block.js',
      'string-noise.js',
      'computed.js',
    ]) {
      fs.writeFileSync(path.join(compiled, fileName), 'export const noise = true;\n');
    }

    copyRendererChannelBuilderRuntime(compiled, renderer);

    const served = path.join(renderer, 'domain', 'channelBuilder');
    assert.deepEqual(fs.readdirSync(served), ['config.js']);
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

test('renderer runtime copy reports unresolved dependencies without absolute paths', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'lineup-renderer-runtime-missing-'));
  const compiled = path.join(root, 'dist', 'domain', 'channelBuilder');
  const renderer = path.join(root, 'dist', 'renderer');
  try {
    fs.mkdirSync(compiled, { recursive: true });
    fs.writeFileSync(path.join(compiled, 'config.js'), "import './missing.js';\n");

    assert.throws(
      () => copyRendererChannelBuilderRuntime(compiled, renderer),
      (error) => {
        assert.equal(
          error.message,
          'Renderer Channel Builder runtime dependency could not be resolved: "./missing.js" imported by "config.js"',
        );
        assert.equal(error.message.includes(root), false);
        return true;
      },
    );
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

test('renderer runtime copy rejects dependencies outside the Channel Builder directory', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'lineup-renderer-runtime-boundary-'));
  const compiled = path.join(root, 'dist', 'domain', 'channelBuilder');
  const renderer = path.join(root, 'dist', 'renderer');
  try {
    fs.mkdirSync(compiled, { recursive: true });
    fs.writeFileSync(path.join(compiled, 'config.js'), "import '../privileged.js';\n");
    fs.writeFileSync(path.join(root, 'dist', 'domain', 'privileged.js'), 'export {};\n');

    assert.throws(
      () => copyRendererChannelBuilderRuntime(compiled, renderer),
      /escapes its allowed directory/u,
    );
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

test('renderer runtime copy rejects the exact parent directory dependency', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'lineup-renderer-runtime-parent-'));
  const compiled = path.join(root, 'dist', 'domain', 'channelBuilder');
  const renderer = path.join(root, 'dist', 'renderer');
  try {
    fs.mkdirSync(compiled, { recursive: true });
    fs.writeFileSync(path.join(compiled, 'config.js'), "import '..';\n");

    assert.throws(
      () => copyRendererChannelBuilderRuntime(compiled, renderer),
      /escapes its allowed directory/u,
    );
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

test('renderer runtime copy rejects dependencies whose symlink target escapes the boundary', (t) => {
  if (process.platform === 'win32') {
    t.skip('Creating symlinks requires privileges that are not guaranteed on Windows CI.');
    return;
  }
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'lineup-renderer-runtime-symlink-'));
  const compiled = path.join(root, 'dist', 'domain', 'channelBuilder');
  const renderer = path.join(root, 'dist', 'renderer');
  try {
    fs.mkdirSync(compiled, { recursive: true });
    const outside = path.join(root, 'outside.js');
    fs.writeFileSync(path.join(compiled, 'config.js'), "import './linked.js';\n");
    fs.writeFileSync(outside, 'export const privileged = true;\n');
    fs.symlinkSync(outside, path.join(compiled, 'linked.js'));

    assert.throws(
      () => copyRendererChannelBuilderRuntime(compiled, renderer),
      /escapes its allowed directory/u,
    );
    assert.equal(
      fs.existsSync(path.join(renderer, 'domain', 'channelBuilder', 'linked.js')),
      false,
    );
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

function sha256(filePath) {
  return crypto.createHash('sha256').update(fs.readFileSync(filePath)).digest('hex');
}
