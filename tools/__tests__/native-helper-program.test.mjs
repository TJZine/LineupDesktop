import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const programPath = path.join(repoRoot, 'src/native-helper/Lineup.NativePlayerHost/Program.cs');

test('native helper resolves libmpv from helper directory or explicit override', async () => {
  const source = await readFile(programPath, 'utf8');

  assert.match(source, /Path\.Combine\(AppContext\.BaseDirectory,\s*"libmpv-2\.dll"\)/u);
  assert.match(source, /args\[index\]\s*==\s*"--libmpv"/u);
  assert.doesNotMatch(source, /libmpvPath\s*=\s*"libmpv-2\.dll"/u);
});

test('native helper emits loaded media metadata from command payload', async () => {
  const source = await readFile(programPath, 'utf8');

  assert.match(source, /CacheLoadedMedia\(msg\)/u);
  assert.match(source, /\["id"\]\s*=\s*currentMediaId/u);
  assert.match(source, /\["title"\]\s*=\s*currentMediaTitle/u);
  assert.doesNotMatch(source, /\["id"\]\s*=\s*"loaded-item"/u);
  assert.doesNotMatch(source, /\["title"\]\s*=\s*"Media Stream"/u);
});

test('native helper tears down mpv before reinitializing and applies mapped public track selection', async () => {
  const source = await readFile(programPath, 'utf8');

  assert.match(source, /if \(mpvContext != IntPtr\.Zero\)\s*\{\s*TeardownMpvContext\(\);/su);
  assert.match(source, /NativeMethods\.mpv_terminate_destroy\(mpvContext\)/u);
  assert.doesNotMatch(source, /ApplySelectedPrivateTracks\(msg\.setup\.selectedPrivateTrackIds\)/u);
  assert.match(source, /currentPlaybackSetup\s*=\s*msg\.setup/u);
  assert.match(
    source,
    /trackState\?\.RefreshTrackMappings\(\);\s*ApplySelectedTracks\(currentPlaybackSetup\?\.selectedTrackIds\);/su,
  );
  assert.match(source, /SetSelectedPublicTrack\("aid", selection\.audio\)/u);
  assert.match(source, /SetSelectedPublicTrack\("sid", selection\.subtitle\)/u);
  assert.match(source, /SetSelectedPublicTrack\("vid", selection\.video\)/u);
  assert.match(source, /trackState\?\.GetMpvTrackId\(publicTrackId\)/u);
});

test('native helper preserves replacement load request id after teardown', async () => {
  const source = await readFile(programPath, 'utf8');

  assert.doesNotMatch(source, /currentRequestId\s*=\s*msg\.requestId;\s*InitializeMpv\(msg\)/u);
  assert.match(
    source,
    /if \(mpvContext != IntPtr\.Zero\)\s*\{\s*TeardownMpvContext\(\);\s*\}\s*currentRequestId\s*=\s*msg\.requestId;\s*EnsureLibmpvResolverRegistered\(\);/su,
  );
});

test('native helper rejects controls before media is loaded', async () => {
  const source = await readFile(programPath, 'utf8');

  assert.match(source, /msg\.command != "load" && mpvContext == IntPtr\.Zero/u);
  assert.match(source, /PLAYER_HELPER_NOT_READY/u);
  assert.match(source, /Player helper has not loaded media\./u);
});
