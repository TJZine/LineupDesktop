import { mkdir, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';

import type { BrowserWindow } from 'electron';

const VIEWPORTS = [
  { label: '1280x720', width: 1280, height: 720 },
  { label: '1920x1080', width: 1920, height: 1080 },
] as const;

export async function runChannelSetupProofAssertions(
  window: BrowserWindow,
  outputDirectory: string,
  phase: 'first-run' | 'relaunch',
): Promise<void> {
  await mkdir(outputDirectory, { recursive: true });
  const captures: string[] = [];
  const capture = async (name: string): Promise<void> => {
    for (const viewport of VIEWPORTS) {
      window.setContentSize(viewport.width, viewport.height);
      await wait(80);
      const fileName = `${phase}-${name}-${viewport.label}.png`;
      const buffer = (await window.webContents.capturePage()).toPNG();
      await writeFile(path.join(outputDirectory, fileName), buffer);
      captures.push(fileName);
    }
  };

  if (phase === 'first-run') {
    await waitFor(window, `document.documentElement.dataset.setupOwner === 'library' && document.querySelectorAll('[data-plex-section-id]').length === 2`);
    await capture('library');
    await selectAllAndOpenPreview(window);
    await waitFor(window, `document.querySelector('[data-staged-owner="preview"]')?.dataset.ownerActive === 'true' && !document.querySelector('[data-focus-id="setup-preview-retry"]')?.hidden`);
    await capture('retryable-error');
    await click(window, '[data-focus-id="setup-preview-retry"]');
    await waitForPreview(window);
    await captureBuilderCategories(window, capture);
    await capture('preview');
    await openReview(window);
    await capture('review');
    await click(window, '[data-focus-id="setup-confirm"]');
    await waitFor(window, `document.querySelector('[data-staged-owner="progress"]')?.dataset.ownerActive === 'true'`);
    await capture('progress-before-cancel');
    await click(window, '[data-focus-id="setup-progress-cancel"]');
    await waitFor(window, `document.querySelector('[data-staged-owner="result"]')?.dataset.ownerActive === 'true' && document.querySelector('[data-builder-result-title]')?.textContent?.includes('canceled')`);
    await capture('pre-apply-canceled-result');
    await click(window, '[data-focus-id="setup-done"]');

    await waitFor(window, `document.documentElement.dataset.activeRoute === 'player'`);
    await click(window, '[data-focus-id="player-setup-reminder"]');
    await prepareBuilder(window, 'append');
    await openReview(window);
    await buildAndWaitForResult(window, capture, 'append');
    await click(window, '[data-focus-id="setup-done"]');

    await key(window, 's');
    await waitFor(window, `document.documentElement.dataset.activeRoute === 'settings'`);
    await click(window, '[data-focus-id="settings-open-channel-setup"]');
    await prepareBuilder(window, 'replace');
    await openReview(window);
    await click(window, '[data-focus-id="builder-replace-confirm"]');
    await buildAndWaitForResult(window, capture, 'replace');
    await click(window, '[data-focus-id="setup-done"]');
    await assertExpression(window, `document.documentElement.dataset.activeRoute === 'settings' && document.activeElement?.getAttribute('data-focus-id') === 'settings-open-channel-setup'`, 'Settings exact return focus');

    await key(window, 'g');
    await waitFor(window, `document.documentElement.dataset.activeRoute === 'guide' && document.querySelector('[data-focus-id="guide-state-setup"]')`);
    await click(window, '[data-focus-id="guide-state-setup"]');
    await prepareBuilder(window, 'merge');
    await captureMediaModes(window, capture);
    await captureFullscreenContinuity(window, capture);
    await openReview(window);
    await buildAndWaitForResult(window, capture, 'merge');
    await click(window, '[data-focus-id="setup-done"]');
    await assertExpression(window, `document.documentElement.dataset.activeRoute === 'guide' && document.activeElement?.getAttribute('data-focus-id') === 'guide-state-setup'`, 'Guide exact return focus');
  } else {
    await waitFor(window, `document.documentElement.dataset.activeRoute === 'player'`);
    await key(window, 's');
    await waitFor(window, `document.documentElement.dataset.activeRoute === 'settings'`);
    await click(window, '[data-focus-id="settings-open-channel-setup"]');
    await waitFor(window, `document.documentElement.dataset.setupOwner === 'library' && document.querySelectorAll('[data-plex-section-id]').length === 2`);
    await selectAllAndOpenPreview(window);
    await waitForPreview(window);
    await click(window, '[data-focus-id="builder-category-build-options"]');
    await waitFor(window, `document.querySelector('[data-focus-id="builder-control-build-mode"]')?.textContent?.includes('Merge')`);
    await capture('record-restored');
    await key(window, 'Escape');
    await waitFor(window, `document.documentElement.dataset.setupOwner === 'library'`);
    await key(window, 'Escape');
    await assertExpression(window, `document.documentElement.dataset.activeRoute === 'settings' && document.activeElement?.getAttribute('data-focus-id') === 'settings-open-channel-setup'`, 'Relaunch Settings return focus');
  }

  await updateManifest(outputDirectory, phase, captures);
}

async function prepareBuilder(window: BrowserWindow, mode: 'append' | 'replace' | 'merge'): Promise<void> {
  await waitFor(window, `document.documentElement.dataset.setupOwner === 'library' && document.querySelectorAll('[data-plex-section-id]').length === 2`);
  await selectAllAndOpenPreview(window);
  await waitForPreview(window);
  if (mode === 'append') return;
  await click(window, '[data-focus-id="builder-category-build-options"]');
  await click(window, '[data-focus-id="builder-control-build-mode"]');
  await click(window, `[data-focus-id="builder-option-build-mode-${mode}"]`);
  await waitForPreview(window);
}

async function selectAllAndOpenPreview(window: BrowserWindow): Promise<void> {
  await click(window, '[data-focus-id="setup-select-all"]');
  await click(window, '[data-staged-owner="library"] [data-focus-id="setup-next"]');
}

async function waitForPreview(window: BrowserWindow): Promise<void> {
  await waitFor(window, `document.querySelector('[data-staged-owner="preview"]')?.dataset.ownerActive === 'true' && document.querySelector('[data-builder-preview-status]')?.textContent?.includes('eligible channels selected')`);
}

async function openReview(window: BrowserWindow): Promise<void> {
  await click(window, '[data-staged-owner="preview"] [data-focus-id="setup-next"]');
  await waitFor(window, `document.querySelector('[data-staged-owner="build"]')?.dataset.ownerActive === 'true' && !document.querySelector('[data-focus-id="setup-confirm"]')?.disabled`);
}

async function buildAndWaitForResult(window: BrowserWindow, capture: (name: string) => Promise<void>, mode: string): Promise<void> {
  await click(window, '[data-focus-id="setup-confirm"]');
  await waitFor(window, `document.querySelector('[data-staged-owner="progress"]')?.dataset.ownerActive === 'true'`);
  await capture(`${mode}-progress`);
  await waitFor(window, `document.querySelector('[data-staged-owner="result"]')?.dataset.ownerActive === 'true' && document.querySelector('[data-channel-setup-result]')?.textContent?.includes('created')`);
  await capture(`${mode}-result`);
}

async function captureBuilderCategories(window: BrowserWindow, capture: (name: string) => Promise<void>): Promise<void> {
  for (const category of ['content-sources', 'advanced-sources', 'build-options', 'series-ordering', 'limits', 'priority-order']) {
    await click(window, `[data-focus-id="builder-category-${category}"]`);
    await capture(`strategy-${category}`);
  }
}

async function captureMediaModes(window: BrowserWindow, capture: (name: string) => Promise<void>): Promise<void> {
  const debuggerApi = window.webContents.debugger;
  if (!debuggerApi.isAttached()) debuggerApi.attach('1.3');
  try {
    await debuggerApi.sendCommand('Emulation.setEmulatedMedia', { features: [{ name: 'prefers-reduced-motion', value: 'reduce' }] });
    await capture('reduced-motion');
    await debuggerApi.sendCommand('Emulation.setEmulatedMedia', { features: [{ name: 'forced-colors', value: 'active' }] });
    await capture('forced-colors');
    await debuggerApi.sendCommand('Emulation.setEmulatedMedia', { features: [] });
  } finally {
    debuggerApi.detach();
  }
}

async function captureFullscreenContinuity(window: BrowserWindow, capture: (name: string) => Promise<void>): Promise<void> {
  const owner = await window.webContents.executeJavaScript(`document.documentElement.dataset.setupOwner`);
  window.setFullScreen(true);
  await wait(150);
  await assertExpression(window, `document.documentElement.dataset.setupOwner === ${JSON.stringify(owner)}`, 'Fullscreen setup owner continuity');
  await capture('fullscreen-continuity');
  window.setFullScreen(false);
  await wait(150);
}

async function click(window: BrowserWindow, selector: string): Promise<void> {
  const clicked = await window.webContents.executeJavaScript(`(() => { const element = document.querySelector(${JSON.stringify(selector)}); if (!(element instanceof HTMLButtonElement) || element.disabled || element.hidden) return false; element.click(); return true; })()`);
  if (clicked !== true) throw new Error(`Channel builder proof could not activate ${selector}.`);
  await wait(30);
}

async function key(window: BrowserWindow, keyValue: string): Promise<void> {
  await window.webContents.executeJavaScript(`document.dispatchEvent(new KeyboardEvent('keydown', { key: ${JSON.stringify(keyValue)}, bubbles: true })); true`);
  await wait(50);
}

async function waitFor(window: BrowserWindow, expression: string, timeoutMs = 8_000): Promise<void> {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (await window.webContents.executeJavaScript(`Boolean(${expression})`) === true) return;
    await wait(40);
  }
  const state = await window.webContents.executeJavaScript(`(async () => JSON.stringify({ route: document.documentElement.dataset.activeRoute, setupOwner: document.documentElement.dataset.setupOwner, onboarding: document.documentElement.dataset.onboardingState, libraryStatus: document.querySelector('[data-setup-library-status]')?.textContent, previewStatus: document.querySelector('[data-builder-preview-status]')?.textContent, previewRetryHidden: document.querySelector('[data-focus-id="setup-preview-retry"]')?.hidden, sections: document.querySelectorAll('[data-plex-section-id]').length, error: document.querySelector('[data-setup-safe-error]')?.textContent, plex: await window.lineupDesktop?.plex?.getSnapshot?.(), record: await window.lineupDesktop?.channelSetup?.getRecord?.() }))()`);
  throw new Error(`Channel builder proof timed out waiting for ${expression}. State: ${String(state)}`);
}

async function assertExpression(window: BrowserWindow, expression: string, label: string): Promise<void> {
  if (await window.webContents.executeJavaScript(`Boolean(${expression})`) !== true) throw new Error(`Channel builder proof failed: ${label}.`);
}

async function updateManifest(outputDirectory: string, phase: string, captures: readonly string[]): Promise<void> {
  const manifestPath = path.join(outputDirectory, 'manifest.json');
  let existing: { phases?: unknown[] } = {};
  try { existing = JSON.parse(await readFile(manifestPath, 'utf8')) as { phases?: unknown[] }; } catch { /* First proof phase. */ }
  await writeFile(manifestPath, `${JSON.stringify({
    proof: 'channel-builder-onboarding-parity',
    dataClassification: 'synthetic-non-private',
    viewports: VIEWPORTS.map(({ label, width, height }) => ({ label, width, height })),
    phases: [...(Array.isArray(existing.phases) ? existing.phases : []), { phase, captures }],
    establishes: ['real Electron IPC/preload/renderer builder journey', 'local exact-viewport rendering', 'synthetic persistence relaunch restoration'],
    doesNotEstablish: ['live Plex compatibility', 'operator-observed Windows input hardware', 'signed installer or public distribution readiness'],
  }, null, 2)}\n`);
}

function wait(durationMs: number): Promise<void> { return new Promise((resolve) => setTimeout(resolve, durationMs)); }
