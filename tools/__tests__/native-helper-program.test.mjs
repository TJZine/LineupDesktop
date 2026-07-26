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

test('native helper uses official mpv format values and structured runtime property setters', async () => {
  const source = await readFile(programPath, 'utf8');

  assert.match(source, /MpvFormatString\s*=\s*1/u);
  assert.match(source, /MpvFormatFlag\s*=\s*3/u);
  assert.match(source, /MpvFormatInt64\s*=\s*4/u);
  assert.match(source, /MpvFormatDouble\s*=\s*5/u);
  assert.match(source, /mpv_set_property\(mpv,\s*name,\s*MpvFormatFlag,\s*data\)/u);
  assert.match(source, /mpv_set_property\(mpv,\s*name,\s*MpvFormatDouble,\s*data\)/u);
  assert.doesNotMatch(source, /SetOption\(mpv,\s*name,\s*value\s*\?\s*"yes"\s*:\s*"no"\)/u);
});

test('native helper keeps credential headers in checked pre-initialize options', async () => {
  const source = await readFile(programPath, 'utf8');

  assert.match(
    source,
    /EnsureOptionSet\(\s*mpvContext,\s*"http-header-fields",[\s\S]*?NativeMethods\.mpv_initialize\(mpvContext\)/u,
  );
  assert.match(source, /if \(SetOption\(mpv,\s*name,\s*value\) < 0\)/u);
  assert.doesNotMatch(
    source,
    /InitializeMpv\(msg\);[\s\S]*?SetOption\(mpvContext,\s*"http-header-fields"/u,
  );
});

test('native helper gates runtime control results and formats seek values invariantly', async () => {
  const source = await readFile(programPath, 'utf8');

  for (const expectedCall of [
    /WriteCommandResult\(msg\.requestId!,\s*SetPropertyBool\(mpvContext,\s*"pause",\s*false\)\)/u,
    /WriteCommandResult\(msg\.requestId!,\s*SetPropertyBool\(mpvContext,\s*"pause",\s*true\)\)/u,
    /WriteCommandResult\(msg\.requestId!,\s*Command\(mpvContext,\s*"stop"\)\)/u,
    /WriteCommandResult\(msg\.requestId!,\s*SetPropertyDouble\(mpvContext,\s*"volume",\s*volume\)\)/u,
    /WriteCommandResult\(msg\.requestId!,\s*SetPropertyBool\(mpvContext,\s*"mute",\s*muted\)\)/u,
  ]) {
    assert.match(source, expectedCall);
  }

  assert.match(
    source,
    /positionSeconds\.ToString\("F3",\s*CultureInfo\.InvariantCulture\)/u,
  );
  assert.match(source, /deltaSeconds\.ToString\("F3",\s*CultureInfo\.InvariantCulture\)/u);
  assert.match(source, /if \(nativeResult >= 0\)[\s\S]*?PLAYER_HELPER_COMMAND_FAILED/u);
  assert.doesNotMatch(source, /PLAYER_HELPER_COMMAND_EXCEPTION/u);
});

test('native helper checks essential property observation registration before starting threads', async () => {
  const source = await readFile(programPath, 'utf8');

  assert.match(
    source,
    /if \(NativeMethods\.mpv_observe_property\(mpv,\s*replyUserdata,\s*name,\s*format\) < 0\)/u,
  );
  assert.match(
    source,
    /ObserveProperty\(mpvContext,\s*1,\s*"time-pos",\s*MpvFormatDouble\)[\s\S]*?ObserveProperty\(mpvContext,\s*10,\s*"audio-codec",\s*MpvFormatString\)[\s\S]*?renderThread\.Start\(\)/u,
  );
  assert.match(
    source,
    /if \(NativeMethods\.mpv_observe_property[\s\S]*?< 0\)\s*\{\s*TeardownMpvContext\(\);\s*throw new InvalidOperationException/u,
  );
});
