import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';

test('Plex composition separates construction from IPC registration', () => {
  const source = fs.readFileSync(
    new URL('../../main/plex/plexComposition.ts', import.meta.url),
    'utf8',
  );
  const ipcSource = fs.readFileSync(
    new URL('../../main/plex/plexIpc.ts', import.meta.url),
    'utf8',
  );
  const createBody = source.slice(
    source.indexOf('export async function createPlexComposition'),
    source.indexOf('export function registerPlexCompositionIpc'),
  );
  assert.doesNotMatch(createBody, /registerPlexIpcHandlers/u);
  assert.match(source, /export function registerPlexCompositionIpc/u);
  assert.match(source, /channelBuilderFacetTransport: liveTransport/u);
  assert.match(source, /libraryTransport: liveTransport/u);
  assert.match(
    source,
    /if \(state\.registrationTeardown === null\) \{\s*await runtime\.shutdown\(\);\s*return;\s*\}\s*await state\.registrationTeardown\(\);/u,
  );
  assert.match(
    ipcSource,
    /return async \(\) => \{\s*await options\.runtime\.shutdown\(\);\s*for \(const channel of PLEX_IPC_CHANNELS\)/u,
  );
});

test('main startup repairs channels before readiness and tears Plex down on later failure', () => {
  const source = fs.readFileSync(
    new URL('../../main/index.ts', import.meta.url),
    'utf8',
  );
  const bootstrap = source.indexOf('new ChannelPersistenceBootstrapOwner');
  const lock = source.indexOf('if (!singleInstanceOwner.acquire().primary) return;');
  const lifecycle = source.indexOf('registerApplicationLifecycleHandlers();');
  const plex = source.indexOf('createPlexComposition(');
  const repair = source.indexOf('new ChannelPersistenceStartupOwner');
  const ready = source.indexOf('app.whenReady()');
  const window = source.indexOf('createShellWindowController(');
  const channelRegistration = source.indexOf('registerChannelCompositionIpc(');
  assert.equal(
    lock < lifecycle &&
      lifecycle < bootstrap &&
      bootstrap < plex &&
      plex < repair &&
      repair < ready &&
      ready < window &&
      window < channelRegistration,
    true,
  );
  assert.equal(source.slice(0, lifecycle).includes("app.on('window-all-closed'"), false);
  assert.equal(source.slice(0, lifecycle).includes("app.on('before-quit'"), false);
  assert.match(source, /plexComposition = plexCreated;/u);
  assert.match(
    source,
    /const teardownChannel = channelComposition\?\.teardown \?\? null;[\s\S]*const teardownPlex = plexComposition\?\.teardown \?\? null;[\s\S]*await Promise\.all\(\[[\s\S]*teardownChannel\?\.\(\)[\s\S]*teardownPlex\?\.\(\)/u,
  );
});
