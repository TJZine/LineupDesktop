import assert from 'node:assert/strict';
import test from 'node:test';

import type {
  ChannelSetupBuildProgress,
  ChannelSetupBuildResult,
  ChannelSetupConfig,
  ChannelSetupConfigDraft,
  ChannelSetupPreview,
  ChannelSetupReview,
} from '../../contracts/channel.js';
import type { LineupDesktopPreloadApi } from '../../contracts/shell.js';
import { createChannelBuilderController, readChannelBuilderAction } from '../../renderer/setup/channelBuilderController.js';
import { renderChannelBuilderDom } from '../../renderer/setup/stagedSetupDom.js';
import { createStagedSetupController, handleStagedSetupBack } from '../../renderer/setup/stagedSetupController.js';

type Bridge = LineupDesktopPreloadApi['channelSetup'];

test('channel builder exposes the public action vocabulary and starts with every upstream strategy enabled in priority order', async () => {
  const previews: ChannelSetupConfigDraft[] = [];
  const controller = createChannelBuilderController({ bridge: bridge({ preview: async (draft) => {
    previews.push(draft); return ok(preview(draft));
  } }), onStateChanged: () => undefined });

  await controller.initialize(['movies']);
  await controller.requestPreview(true);
  const draft = controller.getState().draft;
  assert.deepEqual(Object.entries(draft.strategyConfig).map(([key, value]) => [key, value.enabled, value.priority]), [
    ['playlists', true, 1], ['collections', true, 2], ['recentlyAdded', true, 3], ['genres', true, 4],
    ['studios', true, 5], ['actors', true, 6], ['decades', true, 7], ['directors', true, 8],
  ]);
  assert.equal(previews.length, 1);
  assert.equal(readChannelBuilderAction('selectCategory'), 'selectCategory');
  assert.equal(readChannelBuilderAction('commit'), null);
});

test('channel builder invalidates eligible preview immediately and sends changed strategy, priority, scope, mode, and playback configuration', async () => {
  const previews: ChannelSetupConfigDraft[] = [];
  const controller = createChannelBuilderController({ bridge: bridge({ preview: async (draft) => {
    previews.push(globalThis.structuredClone(draft)); return ok(preview(draft));
  } }), onStateChanged: () => undefined });
  await controller.initialize(['movies', 'shows']);
  await controller.requestPreview(true);

  controller.apply('toggleStrategy', 'playlists');
  assert.equal(controller.getState().phase, 'preview-loading');
  assert.equal(controller.getState().preview, null);
  controller.apply('togglePriorityGrab', 'directors');
  controller.handlePriorityDirection('up');
  controller.apply('togglePriorityGrab', 'directors');
  controller.apply('toggleScopeDropdown', 'genres');
  assert.equal(controller.getState().openScopeDropdown, 'genres');
  controller.apply('selectScope', 'genres:cross-library');
  assert.equal(controller.getState().openScopeDropdown, null);
  controller.apply('toggleAdjustable', 'build-mode');
  assert.equal(controller.getState().openAdjustableControl, 'build-mode');
  assert.equal(controller.getState().focusIntent, 'builder-option-build-mode-append');
  controller.apply('selectAdjustable', 'build-mode:merge');
  controller.apply('selectAdjustable', 'max-channels:150');
  controller.apply('selectAdjustable', 'min-items:5');
  controller.apply('toggleAlternates');
  controller.apply('selectAdjustable', 'alternate-copies:2');
  controller.apply('selectAdjustable', 'variant-type:block');
  controller.apply('selectAdjustable', 'variant-block:3');
  controller.apply('selectAdjustable', 'base-mode:block');
  controller.apply('selectAdjustable', 'base-block:3');
  controller.apply('selectAdjustable', 'combine-mode:combined');
  await controller.requestPreview(true);

  const sent = previews.at(-1)!;
  assert.equal(sent.strategyConfig.playlists?.enabled, false);
  assert.equal(sent.strategyConfig.directors?.priority, 7);
  assert.equal(sent.strategyConfig.genres?.scope, 'cross-library');
  assert.equal(sent.buildMode, 'merge');
  assert.equal(sent.maxChannels, 150);
  assert.equal(sent.minItemsPerChannel, 5);
  assert.equal(sent.channelExpansion?.addAlternateLineups, true);
  assert.equal(sent.channelExpansion?.alternateLineupCopies, 2);
  assert.equal(sent.channelExpansion?.variantType, 'block');
  assert.equal(sent.channelExpansion?.variantBlockSize, 3);
  assert.equal(sent.seriesOrdering?.basePlaybackMode, 'block');
  assert.equal(sent.seriesOrdering?.baseBlockSize, 3);
  assert.equal(sent.actorStudioCombineMode, 'combined');
});

test('rendered Step 2 uses the exact upstream category hierarchy and adjustable listbox semantics', async () => {
  const controller = createChannelBuilderController({ bridge: bridge({}), onStateChanged: () => undefined });
  await controller.initialize(['movies']);
  const documentDouble = new BuilderDocumentDouble();
  renderChannelBuilderDom(controller.getState(), documentDouble as unknown as Document);
  assert.deepEqual(documentDouble.categories.children.map((child) => child.textContent), ['Content Sources', 'Advanced Sources', 'Build Options', 'Series Ordering', 'Limits', 'Guide Order']);

  controller.apply('selectCategory', 'build-options');
  controller.apply('toggleAdjustable', 'build-mode');
  renderChannelBuilderDom(controller.getState(), documentDouble as unknown as Document);
  const buildMode = documentDouble.findByFocusId('builder-control-build-mode');
  assert.equal(buildMode?.attributes.get('aria-haspopup'), 'listbox');
  assert.equal(buildMode?.attributes.get('aria-expanded'), 'true');
  assert.deepEqual(documentDouble.findByRole('option').map((option) => option.textContent), ['Replace', 'Append', 'Merge']);
  assert.equal(documentDouble.all().some((element) => element.dataset.focusId?.includes('-up') || element.dataset.focusId?.includes('-down')), false);
});

test('rendered Guide Order rows move in priority order while grabbed and preserve row focus identity', async () => {
  const controller = createChannelBuilderController({ bridge: bridge({}), onStateChanged: () => undefined });
  await controller.initialize(['movies']);
  controller.apply('selectCategory', 'priority-order');
  const documentDouble = new BuilderDocumentDouble();
  renderChannelBuilderDom(controller.getState(), documentDouble as unknown as Document);
  const before = documentDouble.priorityRows().map((row) => row.dataset.focusId);
  controller.apply('togglePriorityGrab', 'directors');
  assert.equal(controller.handlePriorityDirection('up'), true);
  renderChannelBuilderDom(controller.getState(), documentDouble as unknown as Document);
  const after = documentDouble.priorityRows().map((row) => row.dataset.focusId);
  assert.notDeepEqual(after, before);
  assert.equal(after.at(-2), 'builder-priority-directors');
  assert.equal(controller.getState().focusIntent, 'builder-priority-directors');
  controller.apply('togglePriorityGrab', 'directors');
  assert.equal(controller.getState().grabbedPriorityKey, null);
});

test('Back dismisses adjustable and scope transients with exact trigger focus before a second Back navigates', async () => {
  for (const transient of ['adjustable', 'scope'] as const) {
    const builder = createChannelBuilderController({ bridge: bridge({}), onStateChanged: () => undefined }); await builder.initialize(['movies']);
    const staged = createStagedSetupController({ onStateChanged: () => undefined }); staged.showOwner('preview', 'builder-category-content-sources');
    if (transient === 'adjustable') builder.apply('toggleAdjustable', 'build-mode'); else builder.apply('toggleScopeDropdown', 'genres');
    let backCalls = 0;
    const back = () => handleStagedSetupBack({ controller: staged, builder, customController: {} as Parameters<typeof handleStagedSetupBack>[0]['customController'], plexController: {} as Parameters<typeof handleStagedSetupBack>[0]['plexController'], dispatch: async () => { backCalls += 1; staged.showOwner('library', 'setup-select-all'); } });
    await back();
    assert.equal(staged.getState().owner, 'preview');
    assert.equal(staged.getState().focusIntent, transient === 'adjustable' ? 'builder-control-build-mode' : 'builder-genres-scope');
    assert.equal(backCalls, 0);
    assert.equal(builder.getState().openAdjustableControl, null); assert.equal(builder.getState().openScopeDropdown, null);
    await back();
    assert.equal(backCalls, 1); assert.equal(staged.getState().owner, 'library');
  }
});

test('Back resolves a grabbed Guide Order row before an otherwise open dropdown transient', async () => {
  const controller = createChannelBuilderController({ bridge: bridge({}), onStateChanged: () => undefined }); await controller.initialize(['movies']);
  controller.apply('toggleAdjustable', 'build-mode'); controller.apply('togglePriorityGrab', 'directors');
  assert.equal(controller.dismissTransient(), true); assert.equal(controller.getState().grabbedPriorityKey, null); assert.equal(controller.getState().openAdjustableControl, 'build-mode');
  assert.equal(controller.dismissTransient(), true); assert.equal(controller.getState().openAdjustableControl, null);
});

test('channel builder ignores stale preview completion and reports blocked, slow, retryable, and safe error states', async () => {
  const first = deferred<ReturnType<typeof ok<ChannelSetupPreview>>>();
  let call = 0;
  const timerCallbacks: { slow?: () => void } = {};
  const controller = createChannelBuilderController({
    bridge: bridge({ preview: async (draft) => ++call === 1 ? first.promise : ok(preview(draft, call === 2 ? 'ready' : 'blocked')) }),
    onStateChanged: () => undefined,
    setTimer: (callback, delay) => { if (delay === 1200) timerCallbacks.slow = callback; return 1 as unknown as ReturnType<typeof globalThis.setTimeout>; },
    clearTimer: () => undefined,
  });
  await controller.initialize(['movies']);
  const stale = controller.requestPreview(true);
  controller.apply('selectAdjustable', 'max-channels:150');
  const latest = controller.requestPreview(true);
  timerCallbacks.slow?.();
  assert.equal(controller.getState().slow, true);
  await latest;
  assert.equal(controller.getState().phase, 'preview-ready');
  first.resolve(ok(preview({ ...controller.getState().draft, maxChannels: 1 })));
  await stale;
  assert.equal(controller.getState().preview?.config.maxChannels, 150);

  await controller.requestPreview(true);
  assert.equal(controller.getState().phase, 'preview-blocked');
  controller.apply('retryPreview');
  await Promise.resolve();

  const unsafe = createChannelBuilderController({ bridge: bridge({ preview: async () => ({ ok: false, requestId: 'bad', error: { code: 'CHANNEL_UNKNOWN', operation: 'preview', message: 'token at C:\\secret', retryable: true, recoverable: true } }) }), onStateChanged: () => undefined });
  await unsafe.initialize(['movies']);
  await unsafe.requestPreview(true);
  assert.equal(unsafe.getState().safeError, 'Channel setup could not continue. Try again.');
});

test('review gates build, replace always needs explicit destructive confirmation, progress is monotonic, and accepted cancel awaits terminal result', async () => {
  const terminal = deferred<ReturnType<typeof ok<ChannelSetupBuildResult>>>();
  const callbacks: { progress?: (value: ChannelSetupBuildProgress) => void } = {};
  let buildConfirm: boolean | null = null;
  const controller = createChannelBuilderController({ bridge: bridge({
    preview: async (draft) => ok(preview(draft)),
    review: async (draft) => ok(review(draft)),
    build: async (request, callback) => { buildConfirm = request.confirmReplace; callbacks.progress = callback; return terminal.promise; },
    cancelBuild: async ({ buildId }) => ok({ buildId, status: 'accepted' as const }),
  }), onStateChanged: () => undefined, createBuildId: () => 'build-1' });
  await controller.initialize(['movies']);
  await controller.requestPreview(true);
  controller.apply('selectAdjustable', 'build-mode:replace');
  await controller.requestPreview(true);
  assert.equal(await controller.requestReview(), true);
  assert.equal(await controller.build(0), null);
  controller.apply('confirmReplace');
  const building = controller.build(0);
  assert.equal(buildConfirm, true);
  callbacks.progress?.({ task: 'create_channels', current: 5, total: 10, label: 'Create', detail: 'Five' });
  callbacks.progress?.({ task: 'create_channels', current: 3, total: 10, label: 'Create', detail: 'Three' });
  assert.equal(controller.getState().progress?.current, 5);
  await controller.cancelBuild();
  assert.equal(controller.getState().phase, 'progress');
  assert.equal(controller.getState().cancelStatus, 'accepted');
  terminal.resolve(ok(canceled('build-1')));
  assert.equal((await building)?.kind, 'canceled');
  assert.equal(controller.getState().phase, 'result');
});

test('route invalidation cancels the active build and ignores its later terminal callback', async () => {
  const terminal = deferred<ReturnType<typeof ok<ChannelSetupBuildResult>>>();
  const cancellations: string[] = [];
  const controller = createChannelBuilderController({ bridge: bridge({
    preview: async (draft) => ok(preview(draft)), review: async (draft) => ok(review(draft)),
    build: async (_request, _progress) => terminal.promise,
    cancelBuild: async ({ buildId }) => { cancellations.push(buildId); return ok({ buildId, status: 'accepted' as const }); },
  }), onStateChanged: () => undefined, createBuildId: () => 'build-leave' });
  await controller.initialize(['movies']); await controller.requestPreview(true); await controller.requestReview();
  const building = controller.build(2);
  controller.invalidate();
  assert.deepEqual(cancellations, ['build-leave']);
  terminal.resolve(ok(canceled('build-leave')));
  assert.equal(await building, null);
  assert.equal(controller.getState().phase, 'idle');
});

test('a failed build can safely regenerate review state for an explicit retry', async () => {
  let reviews = 0;
  const controller = createChannelBuilderController({ bridge: bridge({
    preview: async (draft) => ok(preview(draft)),
    review: async (draft) => { reviews += 1; return ok(review(draft)); },
    build: async ({ buildId }) => ok({ kind: 'failed', buildId, counts: counts(), warnings: [], error: { code: 'CHANNEL_UNKNOWN', operation: 'build', message: 'Build failed.', retryable: true, recoverable: true } }),
  }), onStateChanged: () => undefined });
  await controller.initialize(['movies']); await controller.requestPreview(true); await controller.requestReview();
  assert.equal((await controller.build(0))?.kind, 'failed');
  assert.equal(controller.getState().phase, 'error');
  assert.equal(await controller.requestReview(), true);
  assert.equal(reviews, 2);
  assert.equal(controller.getState().phase, 'review-ready');
});

test('review publishes loading and slow states before its bridge result settles', async () => {
  const pending = deferred<ReturnType<typeof ok<ChannelSetupReview>>>(); const timers: { slow?: () => void } = {};
  const controller = createChannelBuilderController({ bridge: bridge({ preview: async (draft) => ok(preview(draft)), review: async () => pending.promise }), onStateChanged: () => undefined, setTimer: (callback, delay) => { if (delay === 1200) timers.slow = callback; return 1 as unknown as ReturnType<typeof globalThis.setTimeout>; }, clearTimer: () => undefined });
  await controller.initialize(['movies']); await controller.requestPreview(true);
  const reviewing = controller.requestReview();
  assert.equal(controller.getState().phase, 'review-loading');
  timers.slow?.(); assert.equal(controller.getState().slow, true);
  pending.resolve(ok(review(controller.getState().draft)));
  assert.equal(await reviewing, true); assert.equal(controller.getState().phase, 'review-ready');
});

function bridge(overrides: Partial<Bridge>): Bridge {
  return {
    getStatus: async () => { throw new Error('legacy status must not be used by the builder'); },
    commit: async () => { throw new Error('legacy commit must not be used by the builder'); },
    getRecord: async () => ok({ status: 'missing' as const }),
    preview: async (draft) => ok(preview(draft)), review: async (draft) => ok(review(draft)),
    build: async ({ buildId }) => ok(committed(buildId)),
    cancelBuild: async ({ buildId }) => ok({ buildId, status: 'not-active' as const }),
    ...overrides,
  };
}
function ok<T>(value: T) { return { ok: true as const, requestId: 'request', value }; }
function preview(draft: ChannelSetupConfigDraft, status: ChannelSetupPreview['status'] = 'ready'): ChannelSetupPreview {
  const config = { ...draft, strategyConfig: draft.strategyConfig, channelExpansion: { addAlternateLineups: false, alternateLineupCopies: 1, variantType: 'none' as const, variantBlockSize: 2, ...draft.channelExpansion }, seriesOrdering: { basePlaybackMode: 'shuffle' as const, baseBlockSize: 2, ...draft.seriesOrdering } } as ChannelSetupConfig;
  return { status, config, estimates: { total: 10, playlists: 1, collections: 1, recentlyAdded: 1, genres: 2, studios: 1, actors: 1, decades: 1, directors: 2 }, eligibleGeneratedCount: 10, selectedGeneratedCount: 10, droppedByMinItemsCount: 0, droppedByPlanCapCount: 0, reachedMaxChannels: false, warnings: [], ...(status === 'blocked' ? { message: 'No channels matched.', failureReason: 'empty' as const } : {}) };
}
function review(draft: ChannelSetupConfigDraft): ChannelSetupReview { return { preview: preview(draft), diff: { summary: { created: 10, removed: draft.buildMode === 'replace' ? 2 : 0, unchanged: 0 }, samples: { created: ['One'], removed: [], unchanged: [] } } }; }
function counts() { return { plannedGeneratedCount: 10, createdCount: 0, updatedCount: 0, preservedCount: 0, removedCount: 0, skippedCount: 0, reachedMaxChannels: false, channelNumberCapacityExhausted: false, errorCount: 0 }; }
function canceled(buildId: string): ChannelSetupBuildResult { return { kind: 'canceled', buildId, counts: counts(), warnings: [] }; }
function committed(buildId: string): ChannelSetupBuildResult { return { kind: 'committed', buildId, counts: counts(), warnings: [], guideRefresh: { kind: 'completed' } }; }
function deferred<T>() { let resolve!: (value: T) => void; const promise = new Promise<T>((done) => { resolve = done; }); return { promise, resolve }; }

class BuilderElementDouble {
  readonly dataset: Record<string, string> = {};
  readonly attributes = new Map<string, string>();
  readonly children: BuilderElementDouble[] = [];
  readonly style: { width?: string } = {};
  className = ''; disabled = false; hidden = false; scrollTop = 0; private ownText = '';
  readonly classList = { add: (...names: string[]) => { this.className = [...new Set([...this.className.split(' ').filter(Boolean), ...names])].join(' '); }, toggle: (name: string, enabled: boolean) => { const names = new Set(this.className.split(' ').filter(Boolean)); if (enabled) names.add(name); else names.delete(name); this.className = [...names].join(' '); } };
  set textContent(value: string) { this.ownText = value; if (value === '') this.children.splice(0); }
  get textContent(): string { return `${this.ownText}${this.children.map((child) => child.textContent).join('')}`; }
  append(...children: BuilderElementDouble[]): void { this.children.push(...children); }
  replaceChildren(...children: BuilderElementDouble[]): void { this.ownText = ''; this.children.splice(0, this.children.length, ...children); }
  setAttribute(name: string, value: string): void { this.attributes.set(name, value); }
  removeAttribute(name: string): void { this.attributes.delete(name); }
  querySelector(): BuilderElementDouble | null { return null; }
}
class BuilderDocumentDouble {
  readonly categories = new BuilderElementDouble(); readonly detail = new BuilderElementDouble();
  readonly documentElement = { dataset: {} as Record<string, string> };
  createElement(): BuilderElementDouble { return new BuilderElementDouble(); }
  querySelector(selector: string): BuilderElementDouble | null { return selector === '[data-builder-categories]' ? this.categories : selector === '[data-builder-detail]' ? this.detail : null; }
  all(): BuilderElementDouble[] { const visit = (node: BuilderElementDouble): BuilderElementDouble[] => [node, ...node.children.flatMap(visit)]; return [...visit(this.categories), ...visit(this.detail)]; }
  findByFocusId(id: string): BuilderElementDouble | undefined { return this.all().find((element) => element.dataset.focusId === id); }
  findByRole(role: string): BuilderElementDouble[] { return this.all().filter((element) => element.attributes.get('role') === role); }
  priorityRows(): BuilderElementDouble[] { return this.all().filter((element) => element.className.split(' ').includes('builder-priority-row')); }
}
