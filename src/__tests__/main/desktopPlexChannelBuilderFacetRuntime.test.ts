import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';

test('desktop Plex runtime owns a dedicated optional builder facet transport', () => {
  const source = fs.readFileSync(
    new URL('../../main/plex/desktopPlexRuntime.ts', import.meta.url),
    'utf8',
  );
  assert.match(source, /channelBuilderFacetTransport\?: LivePlexChannelBuilderFacetTransport/u);
  assert.match(source, /withChannelBuilderFacetSession/u);
  assert.match(source, /ChannelBuilderFacetTransportUnavailableError/u);
  assert.doesNotMatch(source, /channelBuilderFacetTransport\s*\?\?\s*.*libraryTransport/u);
});
