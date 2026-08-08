import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const programPath = path.join(repoRoot, 'src/native-helper/Lineup.NativePlayerHost/Program.cs');

function methodBody(source, signature) {
  const signatureIndex = source.indexOf(signature);
  assert.notEqual(signatureIndex, -1, `missing method: ${signature}`);
  const bodyStart = source.indexOf('{', signatureIndex + signature.length);
  assert.notEqual(bodyStart, -1, `missing method body: ${signature}`);
  let depth = 0;
  for (let index = bodyStart; index < source.length; index += 1) {
    const skippedTo = skipCSharpCommentOrLiteral(source, index);
    if (skippedTo !== null) {
      index = skippedTo - 1;
      continue;
    }
    if (source[index] === '{') depth += 1;
    if (source[index] === '}') depth -= 1;
    if (depth === 0) return source.slice(bodyStart + 1, index);
  }
  assert.fail(`unterminated method body: ${signature}`);
}

function skipCSharpCommentOrLiteral(source, index) {
  const current = source[index];
  const next = source[index + 1];
  if (current === '/' && next === '/') {
    const newline = source.indexOf('\n', index + 2);
    return newline === -1 ? source.length : newline + 1;
  }
  if (current === '/' && next === '*') {
    const end = source.indexOf('*/', index + 2);
    assert.notEqual(end, -1, 'unterminated C# block comment');
    return end + 2;
  }
  if (current === "'") return skipCSharpQuotedLiteral(source, index, "'", false);
  if (current !== '"') return null;

  const prefix = source.slice(Math.max(0, index - 2), index);
  const verbatim = prefix.endsWith('@') || prefix === '@$';
  const interpolated = prefix.endsWith('$') || prefix === '$@';
  if (verbatim) {
    return interpolated
      ? skipCSharpInterpolatedString(source, index, true)
      : skipCSharpQuotedLiteral(source, index, '"', true);
  }

  let quoteCount = 1;
  while (source[index + quoteCount] === '"') quoteCount += 1;
  if (quoteCount >= 3) {
    const delimiter = '"'.repeat(quoteCount);
    const end = source.indexOf(delimiter, index + quoteCount);
    assert.notEqual(end, -1, 'unterminated C# raw string literal');
    return end + quoteCount;
  }
  return interpolated
    ? skipCSharpInterpolatedString(source, index, false)
    : skipCSharpQuotedLiteral(source, index, '"', false);
}

function skipCSharpQuotedLiteral(source, start, quote, verbatim) {
  for (let index = start + 1; index < source.length; index += 1) {
    if (verbatim && source[index] === quote && source[index + 1] === quote) {
      index += 1;
      continue;
    }
    if (!verbatim && source[index] === '\\') {
      index += 1;
      continue;
    }
    if (source[index] === quote) return index + 1;
  }
  assert.fail(`unterminated C# ${quote === "'" ? 'character' : 'string'} literal`);
}

function skipCSharpInterpolatedString(source, start, verbatim) {
  for (let index = start + 1; index < source.length; index += 1) {
    if (verbatim && source[index] === '"' && source[index + 1] === '"') {
      index += 1;
      continue;
    }
    if (!verbatim && source[index] === '\\') {
      index += 1;
      continue;
    }
    if (source[index] === '{' && source[index + 1] === '{') {
      index += 1;
      continue;
    }
    if (source[index] === '}' && source[index + 1] === '}') {
      index += 1;
      continue;
    }
    if (source[index] === '{') {
      index = skipCSharpInterpolationExpression(source, index + 1) - 1;
      continue;
    }
    if (source[index] === '"') return index + 1;
  }
  assert.fail('unterminated C# interpolated string literal');
}

function skipCSharpInterpolationExpression(source, start) {
  let depth = 1;
  for (let index = start; index < source.length; index += 1) {
    const skippedTo = skipCSharpCommentOrLiteral(source, index);
    if (skippedTo !== null) {
      index = skippedTo - 1;
      continue;
    }
    if (source[index] === '{') depth += 1;
    if (source[index] === '}') depth -= 1;
    if (depth === 0) return index + 1;
  }
  assert.fail('unterminated C# interpolation expression');
}

function assertUniqueOrdered(source, earlier, later) {
  const earlierIndexes = findOccurrences(source, earlier);
  const laterIndexes = findOccurrences(source, later);
  assert.equal(earlierIndexes.length, 1, `expected exactly one earlier statement: ${earlier}`);
  assert.equal(laterIndexes.length, 1, `expected exactly one later statement: ${later}`);
  assert.ok(earlierIndexes[0] < laterIndexes[0], `expected ${earlier} before ${later}`);
}

function findOccurrences(source, value) {
  const indexes = [];
  let index = source.indexOf(value);
  while (index !== -1) {
    indexes.push(index);
    index = source.indexOf(value, index + value.length);
  }
  return indexes;
}

test('native helper source inspection ignores braces in C# literals and comments', () => {
  const source = String.raw`
private static void Example()
{
    string normal = "}";
    string escaped = "\\\"}";
    string verbatim = @"}""{";
    string verbatimLeadingQuote = @"""{";
    string interpolatedVerbatimDollarAt = $@"{Format(new[] { "}" })}";
    string interpolatedVerbatimAtDollar = @$"{Format(new[] { "}" })}";
    if (true)
    {
        string raw = """ } """;
        string interpolatedRaw = $""" {Format(new[] { "}" })} """;
        Run();
    }
    string interpolated = $"{Format("}")}";
    char brace = '}';
    // }
    /* { } */
    Finish();
}
`;
  const body = methodBody(source, 'private static void Example()');
  assert.match(body, /Finish\(\);/u);
  assertUniqueOrdered(body, 'Run()', 'Finish()');
  assert.throws(
    () => assertUniqueOrdered(`${body}\nRun();`, 'Run()', 'Finish()'),
    /expected exactly one earlier statement/u,
  );
});

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
    /trackState\?\.RefreshTrackMappings\(\);\s*if \(!ApplySelectedTracks\(currentPlaybackSetup\?\.selectedTrackIds\)\)/su,
  );
  assert.match(source, /SetSelectedPublicTrack\("aid", selection\.audio\)/u);
  assert.match(source, /SetSelectedPublicTrack\("sid", selection\.subtitle\)/u);
  assert.match(source, /SetSelectedPublicTrack\("vid", selection\.video\)/u);
  assert.match(source, /trackState\?\.GetMpvTrackId\(publicTrackId\)/u);
});

test('native helper gates FILE_LOADED on checked initial track selection results', async () => {
  const source = await readFile(programPath, 'utf8');

  assert.match(
    source,
    /if \(!ApplySelectedTracks\(currentPlaybackSetup\?\.selectedTrackIds\)\)\s*\{\s*WriteCommandFailureEvent\(currentRequestId\);\s*continue;\s*\}[\s\S]*?\["type"\]\s*=\s*"media\.loaded"/u,
  );
  assert.match(
    source,
    /bool applied = SetSelectedPublicTrack\("aid", selection\.audio\);\s*applied &= SetSelectedPublicTrack\("sid", selection\.subtitle\);\s*applied &= SetSelectedPublicTrack\("vid", selection\.video\);\s*return applied;/u,
  );
  assert.match(
    source,
    /return MpvCommandExecutor\.SetPropertyString\(mpvContext, property, mpvTrackId\) >= 0;/u,
  );
  assert.match(
    source,
    /private static void WriteCommandFailureEvent[\s\S]*?\["code"\]\s*=\s*"PLAYER_HELPER_COMMAND_FAILED"[\s\S]*?\["category"\]\s*=\s*"helper-failure"/u,
  );
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

  assert.match(source, /MpvFormatNone\s*=\s*0/u);
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

test('native helper queries audio devices in-process and applies requested output options before initialize', async () => {
  const source = await readFile(programPath, 'utf8');

  assert.match(
    source,
    /message\.type == "audio-output\.query"[\s\S]*?HandleAudioOutputQuery\(message\.requestId\)/u,
  );
  assert.match(
    source,
    /NativeMethods\.mpv_create\(\)[\s\S]*?SetOption\(probe,\s*"terminal",\s*"no"\)[\s\S]*?SetOption\(probe,\s*"msg-level",\s*"all=no"\)[\s\S]*?ReadAudioOutputs\(probe\)[\s\S]*?finally[\s\S]*?mpv_terminate_destroy\(probe\)/u,
  );
  assert.match(
    source,
    /mpv_get_property\(context,\s*"audio-device-list",\s*MpvFormatNode,\s*ref node\)/u,
  );
  assert.match(source, /\["type"\]\s*=\s*"audio-output\.result"/u);
  assert.match(
    source,
    /EnsureOptionSet\(mpvContext,\s*"audio-device",\s*msg\.setup\.audioOutputNativeKey\)[\s\S]*?EnsureOptionSet\(mpvContext,\s*"audio-spdif",\s*"dts,dts-hd"\)[\s\S]*?mpv_initialize\(mpvContext\)/u,
  );
  assert.match(
    source,
    /if \(result < 0\)[\s\S]*?try[\s\S]*?node\.format != MpvFormatNodeArray[\s\S]*?finally[\s\S]*?mpv_free_node_contents\(ref node\)/u,
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
  assert.match(
    source,
    /Marshal\.WriteInt64\(data,\s*BitConverter\.DoubleToInt64Bits\(value\)\)/u,
  );
  assert.doesNotMatch(source, /Marshal\.StructureToPtr\(value,\s*data/u);
});

test('native helper checks essential property observation registration before starting event delivery', async () => {
  const source = await readFile(programPath, 'utf8');

  assert.match(
    source,
    /if \(NativeMethods\.mpv_observe_property\(mpv,\s*replyUserdata,\s*name,\s*format\) < 0\)/u,
  );
  assert.match(
    source,
    /ObserveProperty\(mpvContext,\s*1,\s*"time-pos",\s*MpvFormatDouble\)[\s\S]*?ObserveProperty\(mpvContext,\s*10,\s*"audio-codec",\s*MpvFormatString\)[\s\S]*?eventThread\.Start\(\)/u,
  );
  assert.match(
    source,
    /ObserveProperty\(mpvContext,\s*8,\s*"video-params",\s*MpvFormatNone\)/u,
  );
  assert.doesNotMatch(
    source,
    /ObserveProperty\(mpvContext,\s*8,\s*"video-params",\s*MpvFormatString\)/u,
  );
  assert.match(
    source,
    /if \(NativeMethods\.mpv_observe_property[\s\S]*?< 0\)\s*\{\s*TeardownMpvContext\(\);\s*throw new InvalidOperationException/u,
  );
});

test('native helper classifies official end-file reasons without exposing raw mpv values', async () => {
  const source = await readFile(programPath, 'utf8');

  assert.match(
    source,
    /private struct MpvEventEndFileData\s*\{\s*public int reason;\s*public int error;\s*public long playlist_entry_id;\s*public long playlist_insert_id;\s*public int playlist_insert_num_entries;\s*\}/su,
  );
  for (const [name, value] of [
    ['MpvEndFileReasonEof', 0],
    ['MpvEndFileReasonStop', 2],
    ['MpvEndFileReasonQuit', 3],
    ['MpvEndFileReasonError', 4],
    ['MpvEndFileReasonRedirect', 5],
  ]) {
    assert.match(source, new RegExp(`private const int ${name} = ${value};`, 'u'));
  }
  assert.match(source, /else if \(ev\.event_id == MpvEventEndFile\)\s*\{\s*HandleEndFileEvent\(ev\.data\);\s*\}/su);
  assert.match(source, /if \(data == IntPtr\.Zero\)\s*\{\s*WritePlaybackEndedWithError\(false\);/su);
  assert.match(source, /if \(endFile\.reason == MpvEndFileReasonRedirect\)\s*\{\s*return;/su);
  assert.match(
    source,
    /endFile\.reason == MpvEndFileReasonEof \|\|\s*endFile\.reason == MpvEndFileReasonStop \|\|\s*endFile\.reason == MpvEndFileReasonQuit[\s\S]*?\["type"\]\s*=\s*"ended"/u,
  );
  assert.match(source, /WritePlaybackEndedWithError\(endFile\.reason == MpvEndFileReasonError\)/u);
  assert.match(source, /\["code"\]\s*=\s*"PLAYER_HELPER_PLAYBACK_ENDED_WITH_ERROR"/u);
  assert.match(source, /\["category"\]\s*=\s*"engine-failure"/u);
  assert.match(
    source,
    /\["message"\]\s*=\s*"Native playback ended with a player engine error\."/u,
  );
  assert.doesNotMatch(source, /\["(?:reason|error)"\]\s*=\s*endFile\./u);
});

test('native presentation uses one bounded owner thread and a disabled nonactivating child', async () => {
  const source = await readFile(programPath, 'utf8');
  const manifest = await readFile(path.join(path.dirname(programPath), 'app.manifest'), 'utf8');
  assert.match(source, /BlockingCollection<PresentationWork>\(16\)/u);
  assert.match(source, /Name = "LineupPresentationRenderLoop"/u);
  assert.match(source, /0x4E000000/u);
  assert.match(source, /0x08000004/u);
  assert.match(source, /HwndBottom/u);
  assert.match(source, /WM_MOUSEACTIVATE \/ MA_NOACTIVATE/u);
  assert.match(source, /WM_GETOBJECT: no native accessibility provider/u);
  assert.match(source, /AreDpiAwarenessContextsEqual/u);
  assert.match(source, /Math\.Floor\(bounds\.x/u);
  assert.match(source, /Math\.Ceiling\(\(bounds\.x \+ bounds\.width\)/u);
  assert.doesNotMatch(source, /HWND_TOPMOST|HwndTopmost|WS_POPUP/u);
  assert.match(manifest, />PerMonitorV2</u);
});

test('native presentation validates exact input grammar before queueing and rejects duplicate operations', async () => {
  const source = await readFile(programPath, 'utf8');

  assert.match(source, /if \(!HasExactPresentationKeys\(document\.RootElement\)\)\s*\{\s*WritePresentationResult\(message, "rejected"\)/su);
  assert.match(source, /count != 10 \|\| expected\.Count != 0/u);
  assert.match(source, /IsPositiveSafeInteger\(documentEpoch\)/u);
  assert.match(source, /IsNonZeroDecimal\(root\.GetProperty\("parentHwnd"\)\.GetString\(\)\)/u);
  assert.match(source, /mode != "hidden" && loadedRequest\.ValueKind == JsonValueKind\.Null/u);
  assert.match(source, /boundCount != 4 \|\| boundKeys\.Count != 0/u);
  assert.match(source, /width <= 0 \|\| height <= 0 \|\| x \+ width > 1 \|\| y \+ height > 1/u);
  assert.match(source, /if \(!TryAdvancePresentationOperationSequence\(message\.operationId\)\)\s*\{\s*WritePresentationResult\(message, "rejected"\);\s*return;\s*\}/su);
});

test('native helper applies the presentation cap only after parsing the message type', async () => {
  const source = await readFile(programPath, 'utf8');
  const commandLoop = methodBody(source, 'private static void CommandLoop()');

  assert.match(source, /private const int MAX_HELPER_MESSAGE_SIZE = 1024 \* 1024;/u);
  assert.match(source, /private const int MAX_PRESENTATION_MESSAGE_SIZE = 4096;/u);
  assertUniqueOrdered(commandLoop, 'line.Length > MAX_HELPER_MESSAGE_SIZE', 'JsonDocument.Parse(line)');
  assertUniqueOrdered(commandLoop, 'JsonDocument.Parse(line)', 'message.type == "presentation.update" && line.Length > MAX_PRESENTATION_MESSAGE_SIZE');
  assert.doesNotMatch(commandLoop, /Contains\("\\"presentation\.update\\""/u);
});

test('native presentation currentness is epoch, revision, and loaded-request exact', async () => {
  const source = await readFile(programPath, 'utf8');
  const executeWork = methodBody(source, 'private static string ExecutePresentationWork(InputMessage message)');

  assert.match(source, /message\.documentEpoch < latestPresentationEpoch/u);
  assert.match(source, /message\.documentEpoch == latestPresentationEpoch && message\.revision < latestPresentationRevision/u);
  assert.match(source, /!String\.Equals\(latestPresentationLoadedRequestId, message\.loadedRequestId, StringComparison\.Ordinal\)/u);
  assert.match(executeWork, /if \(message\.mode == "hidden"\)[\s\S]*?HidePresentationSurface\(\)[\s\S]*?latestPresentationHidden = true;[\s\S]*?if \(staleRevision\) return "stale";[\s\S]*?return "hidden";/u);
  assert.doesNotMatch(executeWork, /if \(message\.mode == "hidden"\)[\s\S]*?if \(stalePair\) return "stale";/u);
  assert.match(source, /message\.loadedRequestId == null \|\| message\.loadedRequestId != currentRequestId/u);
  assert.match(source, /exactTuple && latestPresentationHidden && message\.mode != "hidden"/u);
  assert.match(executeWork, /latestPresentationHidden = false;\s*return "applied";/u);
});

test('native presentation SetWindowPos outcomes control visibility and acknowledgements', async () => {
  const source = await readFile(programPath, 'utf8');

  assert.match(source, /public bool Show\(\)\s*\{\s*bool shown = NativeMethods\.SetWindowPos[\s\S]*?if \(shown\) Visible = true;\s*return shown;\s*\}/u);
  assert.match(source, /public bool Hide\(\)\s*\{\s*bool hidden = NativeMethods\.SetWindowPos[\s\S]*?if \(hidden\) Visible = false;\s*return hidden;\s*\}/u);
  assert.match(source, /if \(!renderSurface\.Show\(\)\)\s*\{\s*DestroyPresentationResources\(\);\s*return "rejected";\s*\}[\s\S]*?return "applied";/u);
  assert.match(source, /if \(renderSurface == null \|\| renderSurface\.Hide\(\)\) return true;\s*DestroyPresentationResources\(\);\s*return false;/u);
  assert.match(source, /if \(!HidePresentationSurface\(\)\) return "rejected";\s*latestPresentationHidden = true;\s*if \(staleRevision\) return "stale";/u);
});

test('native presentation contains rejected work and fails the shared lifecycle on asynchronous rendering errors', async () => {
  const source = await readFile(programPath, 'utf8');
  const presentationLoop = methodBody(source, 'private static void PresentationLoop()');
  const failureContainment = methodBody(source, 'private static void ContainPresentationFailure()');
  const lifecycleFailure = methodBody(source, 'private static void FailPresentationLifecycle()');
  const renderFrame = methodBody(source, 'private static void RenderFrame()');

  assert.match(presentationLoop, /catch\s*\{\s*ContainPresentationFailure\(\);\s*work\.Status = "rejected";\s*\}\s*finally\s*\{\s*work\.Completed\.Set\(\);/u);
  assert.match(presentationLoop, /try\s*\{\s*RenderFrame\(\);\s*PumpWindowMessages\(\);\s*\}\s*catch\s*\{\s*FailPresentationLifecycle\(\);\s*return;/u);
  assert.match(failureContainment, /try\s*\{\s*HidePresentationSurface\(\);\s*\}\s*catch\s*\{\s*\}\s*DestroyPresentationResources\(\);\s*latestPresentationHidden = true;/u);
  assertUniqueOrdered(lifecycleFailure, 'ContainPresentationFailure()', 'Environment.Exit(1)');
  assert.match(renderFrame, /if \(!renderSurface\.MakeCurrent\(\)\) throw new InvalidOperationException\(\);/u);
  assert.match(renderFrame, /if \(!NativeMethods\.SwapBuffers\(renderSurface\.DeviceContext\)\) throw new InvalidOperationException\(\);/u);
});

test('native presentation resources are destroyed by their owner before mpv teardown', async () => {
  const source = await readFile(programPath, 'utf8');
  const teardown = methodBody(source, 'private static void TeardownMpvContext()');
  const cleanup = methodBody(source, 'private static void HandleCleanup(string? requestId)');
  const command = methodBody(source, 'private static void HandleCommand(InputMessage msg)');

  assert.doesNotMatch(teardown, /renderContext|renderSurface|DestroyPresentationResources/u);
  assertUniqueOrdered(cleanup, 'DestroyPresentationOnOwnerThread()', 'TeardownMpvContext()');
  assertUniqueOrdered(command, 'DestroyPresentationOnOwnerThread()', 'InitializeMpv(msg)');
});

test('native presentation operation ids reject every replay and nonincreasing sequence', async () => {
  const source = await readFile(programPath, 'utf8');

  assert.match(source, /private static BigInteger latestPresentationOperationSequence = BigInteger\.Zero;/u);
  assert.match(source, /private static bool TryAdvancePresentationOperationSequence\(string operationId\)/u);
  assert.match(source, /const string prefix = "presentation-";/u);
  assert.match(source, /!operationId\.StartsWith\(prefix, StringComparison\.Ordinal\)/u);
  assert.match(source, /!BigInteger\.TryParse\(operationId\.Substring\(prefix\.Length\), NumberStyles\.None, CultureInfo\.InvariantCulture, out BigInteger sequence\)/u);
  assert.match(source, /sequence <= latestPresentationOperationSequence\)\s*\{\s*return false;\s*\}\s*latestPresentationOperationSequence = sequence;\s*return true;/su);
});

test('native presentation duplicate custody is constant-space with no finite retention cap', async () => {
  const source = await readFile(programPath, 'utf8');
  const advanceSequence = methodBody(source, 'private static bool TryAdvancePresentationOperationSequence(string operationId)');

  assert.doesNotMatch(source, /PresentationOperationIds|PresentationOperationIdOrder|PresentationOperationIdCapacity/u);
  assert.match(advanceSequence, /sequence <= latestPresentationOperationSequence/u);
  assert.match(advanceSequence, /latestPresentationOperationSequence = sequence;/u);
  assert.doesNotMatch(advanceSequence, /HashSet|Queue|Dictionary|List/u);
});
