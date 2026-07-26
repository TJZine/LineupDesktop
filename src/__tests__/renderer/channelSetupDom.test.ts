import assert from 'node:assert/strict';
import test from 'node:test';

import {
  createChannelBuilderConfigRows,
  createChannelBuilderReview,
} from '../../renderer/channelSetup/viewModel.js';
import { createChannelBuilderConfigState } from '../../renderer/channelSetup/builderConfigState.js';
import { renderChannelBuilderDom } from '../../renderer/channelSetup/dom.js';
import { createStagedSetupController } from '../../renderer/setup/stagedSetupController.js';
import { dispatchStagedSetupAction } from '../../renderer/setup/stagedSetupController.js';
import { getStagedSetupNeighbors } from '../../renderer/setup/stagedSetupFocus.js';

test('channel setup configuration projection exposes every normalized strategy control', () => {
  const created = createChannelBuilderConfigState({
    serverId: 'server',
    selectedLibraryIds: ['library'],
  });
  assert.equal(created.ok, true);
  if (!created.ok) return;
  const rows = createChannelBuilderConfigRows(created.state.config);
  assert.deepEqual(rows.map((row) => row.key), [
    'collections',
    'playlists',
    'genres',
    'directors',
    'decades',
    'recentlyAdded',
    'studios',
    'actors',
  ]);
  assert.deepEqual(
    rows.filter((row) => row.scopeEditable).map((row) => row.key),
    ['genres', 'directors', 'studios', 'actors'],
  );
  assert.equal(rows.every((row) => Number.isInteger(row.priority)), true);
});

test('channel setup review projects exact counts, samples, warnings, cap, and slow state', () => {
  const review = createChannelBuilderReview({
    operationId: `channel-builder-review-${'a'.repeat(32)}`,
    kind: 'review',
    state: 'review-ready',
    phase: 'review-ready',
    startedAtMs: 1,
    updatedAtMs: 2,
    progress: { completed: 1, total: 1 },
    result: {
      kind: 'review',
      planId: `channel-builder-plan-${'b'.repeat(32)}`,
      contextEpoch: 3,
      lineupRevision: 4,
      status: 'slow',
      diff: {
        summary: { created: 2, removed: 1, unchanged: 5 },
        samples: {
          created: ['A', 'B'],
          removed: ['C'],
          unchanged: ['D'],
        },
      },
      warnings: [{
        code: 'MAX_CHANNELS_REACHED',
        phase: 'planning',
        strategy: null,
        affectedCount: 7,
      }],
      reachedCap: true,
    },
    error: null,
  });
  assert.deepEqual(review.counts, { created: 2, removed: 1, unchanged: 5 });
  assert.deepEqual(review.samples.created, ['A', 'B']);
  assert.deepEqual(review.warnings, ['The configured maximum channel count was reached (7).']);
  assert.equal(review.status, 'slow');
  assert.equal(review.reachedCap, true);
  assert.equal(review.canApply, true);
});

test('blocked review cannot apply and an absent review is unavailable', () => {
  assert.equal(createChannelBuilderReview(null).canApply, false);
  const blocked = createChannelBuilderReview({
    operationId: `channel-builder-review-${'c'.repeat(32)}`,
    kind: 'review',
    state: 'review-ready',
    phase: 'review-ready',
    startedAtMs: 1,
    updatedAtMs: 2,
    progress: { completed: 1, total: 1 },
    result: {
      kind: 'review',
      planId: null,
      contextEpoch: 0,
      lineupRevision: 0,
      status: 'blocked',
      diff: {
        summary: { created: 0, removed: 0, unchanged: 0 },
        samples: { created: [], removed: [], unchanged: [] },
      },
      warnings: [{
        code: 'PLAN_EMPTY',
        phase: 'planning',
        strategy: null,
        affectedCount: null,
      }],
      reachedCap: false,
    },
    error: null,
  });
  assert.equal(blocked.status, 'blocked');
  assert.equal(blocked.canApply, false);
  assert.deepEqual(blocked.warnings, ['No eligible channels were found for this configuration.']);
});

test('rendered builder DOM exposes every control family and enforces dependent disabled states', () => {
  const controller = createStagedSetupController({ onStateChanged: () => undefined });
  assert.equal(controller.prepareBuilderConfig({
    serverId: 'server',
    selectedLibraryIds: ['library'],
  }, {
    completion: 'unknown',
    normalizedConfig: null,
    completedAtMs: null,
  }), true);
  assert.equal(controller.applyBuilderConfigAction('strategyToggle:genres'), true);
  const doc = createBuilderDocument();
  renderChannelBuilderDom({
    state: controller.getState(),
    channelState: {
      summary: null,
      operation: reviewOperation('slow', [{
        code: 'EXISTING_SOURCE_UNMATCHABLE',
        phase: 'planning',
        strategy: null,
        affectedCount: 2,
      }]),
      statusText: 'Channel review ready',
      errorText: null,
      pending: false,
    },
    progress: {
      kind: 'review',
      state: 'review-ready',
      phase: 'review-ready',
      progress: { completed: 1, total: 1 },
      pending: false,
      statusText: 'Channel review ready',
      canCancel: false,
    },
    documentRef: doc as unknown as Document,
  });
  const buttons = descendants(doc.configHost).filter((element) => element.tagName === 'BUTTON');
  const byFocus = new Map(buttons.map((button) => [button.dataset.focusId, button]));
  assert.equal(byFocus.has('channel-strategy-build-append'), true);
  assert.equal(byFocus.has('builder-max-up'), true);
  assert.equal(byFocus.has('builder-genres-toggle'), true);
  assert.equal(byFocus.has('builder-alternate-copies'), true);
  assert.equal(byFocus.has('builder-variant-type'), true);
  assert.equal(byFocus.has('builder-series-mode'), true);
  assert.equal(byFocus.get('builder-genres-priority-up')?.disabled, true);
  assert.equal(byFocus.get('builder-genres-scope')?.disabled, true);
  assert.equal(byFocus.get('builder-alternate-copies')?.disabled, true);
  assert.equal(byFocus.get('builder-variant-block')?.disabled, true);
  assert.equal(byFocus.get('builder-series-block')?.disabled, true);
  assert.match(doc.validation.textContent, /Some existing channels can be retained but cannot be matched or updated by Channel Builder\./u);
  assert.match(doc.impact.textContent, /slow or partial discovery/u);
  assert.equal(doc.regularApply.hidden, true);
  assert.equal(doc.replaceApply.hidden, false);
});

test('replacement modal actions trap focus and restore the exact invoking control', async () => {
  const controller = createStagedSetupController({ onStateChanged: () => undefined });
  controller.showOwner('build', 'setup-confirm-replace');
  controller.setBuildMode('replace');
  await dispatchStagedSetupAction({
    action: 'openReplaceConfirm',
    controller,
  } as never);
  assert.equal(controller.getState().owner, 'replace-confirm');
  assert.equal(controller.getState().focusIntent, 'setup-replace-cancel');
  const modalDoc = activeModalDocument();
  assert.deepEqual(getStagedSetupNeighbors('setup-replace-cancel', modalDoc), {
    up: 'setup-replace-cancel',
    down: 'setup-replace-confirm',
    left: 'setup-replace-cancel',
    right: 'setup-replace-cancel',
  });
  assert.deepEqual(getStagedSetupNeighbors('setup-replace-confirm', modalDoc), {
    up: 'setup-replace-cancel',
    down: 'setup-replace-confirm',
    left: 'setup-replace-confirm',
    right: 'setup-replace-confirm',
  });
  await dispatchStagedSetupAction({
    action: 'cancelReplaceConfirm',
    controller,
  } as never);
  assert.equal(controller.getState().owner, 'build');
  assert.equal(controller.getState().focusIntent, 'setup-confirm-replace');
});

function reviewOperation(
  status: 'ready' | 'slow' | 'blocked',
  warnings: readonly {
    code: 'EXISTING_SOURCE_UNMATCHABLE';
    phase: 'planning';
    strategy: null;
    affectedCount: number;
  }[] = [],
) {
  return {
    operationId: `channel-builder-review-${'d'.repeat(32)}`,
    kind: 'review' as const,
    state: 'review-ready' as const,
    phase: 'review-ready' as const,
    startedAtMs: 1,
    updatedAtMs: 2,
    progress: { completed: 1, total: 1 },
    result: {
      kind: 'review' as const,
      planId: status === 'blocked' ? null : `channel-builder-plan-${'e'.repeat(32)}`,
      contextEpoch: 1,
      lineupRevision: 1,
      status,
      diff: {
        summary: { created: 2, removed: 1, unchanged: 3 },
        samples: { created: ['A'], removed: ['B'], unchanged: ['C'] },
      },
      warnings,
      reachedCap: false,
    },
    error: null,
  };
}

class ElementDouble {
  textContent = '';
  className = '';
  hidden = false;
  disabled = false;
  type = '';
  readonly tagName: string;
  readonly dataset: Record<string, string> = {};
  readonly attributes = new Map<string, string>();
  readonly children: ElementDouble[] = [];
  readonly style: { width?: string } = {};
  readonly classList = {
    toggle: (name: string, enabled: boolean) => {
      const names = new Set(this.className.split(' ').filter(Boolean));
      if (enabled) names.add(name);
      else names.delete(name);
      this.className = [...names].join(' ');
    },
  };
  constructor(tagName = 'div') { this.tagName = tagName.toUpperCase(); }
  append(...children: ElementDouble[]): void { this.children.push(...children); }
  replaceChildren(...children: ElementDouble[]): void {
    this.children.splice(0, this.children.length, ...children);
  }
  setAttribute(name: string, value: string): void { this.attributes.set(name, value); }
  removeAttribute(name: string): void { this.attributes.delete(name); }
  querySelector<T>(selector: string): T | null {
    return selector === 'span' ? this.children[0] as T ?? null : null;
  }
}

class BuilderDocumentDouble {
  readonly configHost = new ElementDouble('section');
  readonly reviewHost = new ElementDouble('div');
  readonly impact = new ElementDouble('div');
  readonly validation = new ElementDouble('div');
  readonly regularApply = new ElementDouble('button');
  readonly replaceApply = new ElementDouble('button');
  readonly cancel = new ElementDouble('button');
  readonly status = new ElementDouble('p');
  readonly progress = new ElementDouble('div');
  constructor() {
    this.progress.append(new ElementDouble('span'));
  }
  createElement(tagName: string): ElementDouble { return new ElementDouble(tagName); }
  querySelector<T>(selector: string): T | null {
    const entries: Record<string, ElementDouble> = {
      '[data-channel-builder-config]': this.configHost,
      '[data-staged-owner="build"] [data-channel-review-list]': this.reviewHost,
      '[data-channel-review-impact]': this.impact,
      '[data-channel-review-validation]': this.validation,
      '[data-focus-id="setup-confirm"]': this.regularApply,
      '[data-focus-id="setup-confirm-replace"]': this.replaceApply,
      '[data-focus-id="setup-progress-cancel"]': this.cancel,
      '[data-channel-operation-status]': this.status,
      '.setup-progress-bar': this.progress,
    };
    return entries[selector] as T ?? null;
  }
}

function createBuilderDocument(): BuilderDocumentDouble {
  return new BuilderDocumentDouble();
}

function descendants(root: ElementDouble): ElementDouble[] {
  return root.children.flatMap((child) => [child, ...descendants(child)]);
}

function activeModalDocument(): Document {
  const elements = ['setup-replace-cancel', 'setup-replace-confirm'].map((focusId) => ({
    dataset: { focusId },
    disabled: false,
    closest: () => null,
    getAttribute: () => null,
  }));
  const root = { querySelectorAll: () => elements };
  return {
    documentElement: { dataset: { setupOwner: 'replace-confirm' } },
    querySelector: (selector: string) =>
      selector === '[data-staged-owner="replace-confirm"]' ? root : null,
    querySelectorAll: () => elements,
  } as unknown as Document;
}
