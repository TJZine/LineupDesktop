import type { ShellWindow } from './window/shellWindowController.js';

import { LINEUP_SHELL_URL } from '../contracts/shell.js';
import { LINEUP_CSP } from './protocol.js';
import {
  assertFullscreenContinuity,
  assertRendererCloseLifecycle,
} from './smokeFullscreenAssertions.js';
import { GUIDE_SMOKE_ASSERTIONS_SOURCE } from './smokeGuideAssertions.js';
import {
  CHANNEL_BUILDER_BRIDGE_ASSERTIONS_SOURCE,
  CHANNEL_BUILDER_FLOW_ASSERTIONS_SOURCE,
} from './smokeChannelBuilderAssertions.js';

const PACKAGE_ONE_GUIDE_SMOKE_ASSERTIONS_SOURCE = GUIDE_SMOKE_ASSERTIONS_SOURCE.replace(
  `      const guideButton = document.querySelector('[data-route-button="guide"]');
      if (!(guideButton instanceof HTMLButtonElement)) {
        failures.push('guide route button');
      } else {
        guideButton.click();
      }`,
  `      document.dispatchEvent(new KeyboardEvent('keydown', { key: 'g', bubbles: true }));
      await new Promise((resolve) => setTimeout(resolve, 0));`,
).replace(
  `      if (!(offRouteOverlayAction instanceof HTMLButtonElement) || !offRouteOverlayAction.disabled) {
        failures.push('off-route overlay action disabled');
      }`,
  `      if (offRouteOverlayAction instanceof HTMLButtonElement && !offRouteOverlayAction.disabled) {
        failures.push('off-route overlay action enabled');
      }`,
);

export interface ShellContainmentCounters {
  navigationDenied: number;
  windowOpenDenied: number;
  permissionDenied: number;
  webviewDenied: number;
}

export async function runSmokeAssertions(
  window: ShellWindow,
  containmentCounters: ShellContainmentCounters,
): Promise<void> {
  const result = await window.webContents.executeJavaScript(`
    (async () => {
      const failures = [];
      const csp = document.querySelector("meta[http-equiv='Content-Security-Policy']")?.content;
      const expectedCsp = ${JSON.stringify(LINEUP_CSP)};

      if (document.documentElement.dataset.shellBoot !== 'ready') failures.push('renderer boot');
      if (location.href !== ${JSON.stringify(LINEUP_SHELL_URL)}) failures.push('shell url');
      if (!document.querySelector('[data-shell-status]')?.textContent?.includes('ready')) {
        failures.push('status event');
      }
      if (csp !== expectedCsp) failures.push('csp meta');
      if (document.documentElement.dataset.activeRoute === 'channelSetup') {
        const firstRunSetup = document.querySelector('[data-screen="channelSetup"]');
        if (!(firstRunSetup instanceof HTMLElement) || firstRunSetup.hidden) {
          failures.push('first-run channel setup route');
        }
        document.dispatchEvent(new KeyboardEvent('keydown', { key: 's', bubbles: true }));
        await new Promise((resolve) => setTimeout(resolve, 0));
        document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));
        document.dispatchEvent(new KeyboardEvent('keyup', { key: 'Escape', bubbles: true }));
        await new Promise((resolve) => setTimeout(resolve, 0));
      }
      try {
        Function('return 1')();
        failures.push('csp unsafe eval');
      } catch {}
      const rootStyle = getComputedStyle(document.documentElement);
      const appShell = document.querySelector('[data-style-surface="app-shell"]');
      const screenRoot = document.querySelector('[data-static-screen-root]');
      const screenStack = document.querySelector('[data-static-screens-mounted]');
      const styledPlayerScreen = document.querySelector('[data-screen="player"]');
      const playerSurface = document.querySelector('[data-player-presentation-surface]');
      const playerFocusButton = document.querySelector('[data-focus-id="overlay-player-retry"]');
      const stylesheetTexts = [];
      for (const sheet of Array.from(document.styleSheets)) {
        try {
          stylesheetTexts.push(...Array.from(sheet.cssRules ?? [], (rule) => rule.cssText));
        } catch {
          failures.push('stylesheet rules readable');
        }
      }
      const stylesheetText = stylesheetTexts.join('\\n');
      if (rootStyle.getPropertyValue('--lineup-style-ready').trim() !== 'unit-6') {
        failures.push('unit 6 stylesheet token');
      }
      if (rootStyle.getPropertyValue('--color-focus').trim() !== '#79c7ff') {
        failures.push('focus token');
      }
      if (!(appShell instanceof HTMLElement) || getComputedStyle(appShell).display !== 'grid') {
        failures.push('app shell style loaded');
      }
      if (document.querySelector('.app-shell__topbar, [data-style-surface="route-rail"], [data-focus-id^="nav-"]')) {
        failures.push('removed shell chrome present');
      }
      if (
        !(styledPlayerScreen instanceof HTMLElement) ||
        getComputedStyle(styledPlayerScreen).borderRadius !== '0px'
      ) {
        failures.push('screen style loaded');
      }
      if (
        !(screenRoot instanceof HTMLElement) ||
        !(screenStack instanceof HTMLElement) ||
        !(styledPlayerScreen instanceof HTMLElement) ||
        !(playerSurface instanceof HTMLElement)
      ) {
        failures.push('screen height style target');
      } else {
        const rootHeight = screenRoot.getBoundingClientRect().height;
        const stackHeight = screenStack.getBoundingClientRect().height;
        const screenHeight = styledPlayerScreen.getBoundingClientRect().height;
        const surfaceHeight = playerSurface.getBoundingClientRect().height;
        if (
          rootHeight < window.innerHeight * 0.6 ||
          Math.abs(stackHeight - rootHeight) > 1 ||
          Math.abs(screenHeight - rootHeight) > 1 ||
          Math.abs(surfaceHeight - screenHeight) > 2.5
        ) {
          failures.push(
            'screen fills grid height ' +
              JSON.stringify({ rootHeight, stackHeight, screenHeight, surfaceHeight }),
          );
        }
      }
      if (!(playerFocusButton instanceof HTMLButtonElement)) {
        failures.push('focus style target');
      } else {
        playerFocusButton.classList.add('is-focused');
        const focusStyle = getComputedStyle(playerFocusButton);
        if (focusStyle.outlineStyle !== 'solid' || focusStyle.outlineWidth !== '3px') {
          failures.push('focus style loaded');
        }
        playerFocusButton.classList.remove('is-focused');
      }
      if (!stylesheetText.includes('@media (prefers-reduced-motion: reduce)')) {
        failures.push('reduced motion style policy');
      }
      if (!stylesheetText.includes('@media (forced-colors: active)')) {
        failures.push('forced colors style policy');
      }
      for (const name of ['process', 'require', 'Buffer']) {
        if (typeof window[name] !== 'undefined') failures.push(name);
      }
      for (const name of ['ipcRenderer', 'electron']) {
        if (typeof window[name] !== 'undefined') failures.push(name);
      }
      const bridge = window.lineupDesktop;
      if (!bridge || typeof bridge !== 'object') failures.push('lineupDesktop bridge');
      if (!bridge?.shell?.getCapabilities) failures.push('shell api');
      if (!bridge?.shell?.onStatusChanged) failures.push('status api');
      if (!bridge?.window?.setFullscreen) failures.push('window api');
      if (!bridge?.player?.dispatch) failures.push('player dispatch api');
      if (!bridge?.player?.getSnapshot) failures.push('player snapshot api');
      if (!bridge?.player?.cleanup) failures.push('player cleanup api');
      if (!bridge?.player?.updatePresentation) failures.push('player presentation api');
      if (!bridge?.player?.onEvent) failures.push('player event api');
      const assertBridgeMethods = (namespace, methods) => {
        const api = bridge?.[namespace];
        if (!api || typeof api !== 'object') {
          failures.push(namespace + ' api');
          return;
        }
        for (const method of methods) {
          if (typeof api[method] !== 'function') {
            failures.push(namespace + ' api method ' + method);
          }
        }
      };
      assertBridgeMethods('diagnostics', ['recordRendererEvent', 'getSummary', 'exportSupportBundle']);
      assertBridgeMethods('plex', [
        'getSnapshot', 'requestPin', 'pollPin', 'cancelPin', 'getHomeUsers', 'switchHomeUser',
        'restoreSelectedServer', 'refreshServers', 'selectServer', 'listLibrarySections',
        'listLibraryItems', 'searchLibrary', 'getMetadata',
      ]);
      ${CHANNEL_BUILDER_BRIDGE_ASSERTIONS_SOURCE}
      assertBridgeMethods('guide', ['getPresentation']);
      if (bridge && typeof bridge === 'object' && 'ipcRenderer' in bridge) failures.push('raw ipc bridge');
      if (bridge && typeof bridge === 'object' && 'invoke' in bridge) failures.push('raw invoke bridge');
      if (failures.length > 0) return { failures };

      const capabilities = await bridge.shell.getCapabilities();
      if (!capabilities.ok || capabilities.value.protocolOrigin !== 'lineup://shell') {
        failures.push('capabilities ' + JSON.stringify(capabilities));
      }
      const playerEvents = [];
      const unsubscribe = bridge.player.onEvent((event) => {
        playerEvents.push(event);
        if (event && typeof event === 'object' && ('sender' in event || 'ports' in event)) {
          failures.push('raw player event object');
        }
      });
      const playerResult = await bridge.player.dispatch({
        intent: 'player.load',
        requestId: 'smoke-player-load',
        payload: {
          media: {
            id: 'smoke-media',
            title: 'Smoke Media',
            durationMs: 1000,
            container: 'smoke',
          },
          policy: {
            autoplay: true,
            startPositionMs: 0,
            preferredAudioTrackId: null,
            preferredSubtitleTrackId: null,
          },
          capabilityProfileId: 'smoke-fake-host',
          seekSupport: 'supported',
        },
      });
      const invalidPlayerResult = await bridge.player.dispatch({
        intent: 'player.play',
        requestId: 'smoke-player-invalid',
      });
      const playerSnapshot = await bridge.player.getSnapshot();
      const cleanup = await bridge.player.cleanup();
      unsubscribe();
      const beforeUnsubscribeCount = playerEvents.length;
      await bridge.player.dispatch({
        intent: 'player.play',
        requestId: 'smoke-player-after-unsubscribe',
        payload: {},
      });
      if (playerEvents.length !== beforeUnsubscribeCount) {
        failures.push('player unsubscribe');
      }
      if (!playerResult.ok || !playerResult.value.accepted || playerResult.requestId !== 'smoke-player-load') {
        failures.push('player dispatch ' + JSON.stringify(playerResult));
      }
      if (invalidPlayerResult.ok || invalidPlayerResult.requestId !== 'smoke-player-invalid') {
        failures.push('player invalid request id ' + JSON.stringify(invalidPlayerResult));
      }
      if (!playerSnapshot.ok || playerSnapshot.value.media?.id !== 'smoke-media') {
        failures.push('player snapshot ' + JSON.stringify(playerSnapshot));
      }
      if (!cleanup.ok || cleanup.value.status !== 'idle') {
        failures.push('player cleanup ' + JSON.stringify(cleanup));
      }
      if (!playerEvents.some((event) => event.event === 'state.changed')) {
        failures.push('player event delivery');
      }
      const numericZIndex = (element) => {
        const value = Number.parseInt(getComputedStyle(element).zIndex, 10);
        return Number.isFinite(value) ? value : 0;
      };
      const assertTopElementAtCenter = (element, label) => {
        if (!(element instanceof HTMLElement)) {
          failures.push(label + ' target');
          return;
        }
        const rect = element.getBoundingClientRect();
        const x = rect.left + rect.width / 2;
        const y = rect.top + rect.height / 2;
        const topElement = document.elementFromPoint(x, y);
        if (topElement === null || (topElement !== element && !element.contains(topElement))) {
          failures.push(
            label +
              ' top element ' +
              JSON.stringify({
                expected: element.getAttribute('data-overlay') ?? element.className,
                rect: {
                  left: rect.left,
                  top: rect.top,
                  width: rect.width,
                  height: rect.height
                },
                coords: { x, y },
                window: { width: window.innerWidth, height: window.innerHeight },
                actual:
                  topElement instanceof HTMLElement
                    ? {
                        tag: topElement.tagName.toLowerCase(),
                        id: topElement.id,
                        class: topElement.className,
                        overlay: topElement.getAttribute('data-overlay'),
                        rect: topElement.getBoundingClientRect()
                      }
                    : null,
              }),
          );
        }
      };
      ${PACKAGE_ONE_GUIDE_SMOKE_ASSERTIONS_SOURCE}

      const semanticStructureFailures = [];
      const follows = (before, after) => (before.compareDocumentPosition(after) & Node.DOCUMENT_POSITION_FOLLOWING) !== 0;
      for (const surfaceName of ['splash', 'loading']) {
        const surface = document.querySelector('[data-shell-surface="' + surfaceName + '"]');
        if (!(surface instanceof HTMLElement)) {
          semanticStructureFailures.push(surfaceName + ' shell surface missing');
          continue;
        }
        const markImages = surface.querySelectorAll('img[src="./assets/lineup-logo-mark.png"]');
        const wordmarkImages = surface.querySelectorAll('img[src="./assets/lineup-wordmark.png"]');
        if (markImages.length !== 1 || wordmarkImages.length !== 1) {
          semanticStructureFailures.push(surfaceName + ' brand assets not owner-local and unique');
        }
      }

      const setupOwnerExpectations = [
        ['library', 'Step 1 of 3', true],
        ['preview', 'Step 2 of 3', false],
        ['build', 'Step 3 of 3', false],
        ['progress', 'Step 3 of 3', false],
        ['result', 'Step 3 of 3', false],
      ];
      for (const [ownerName, expectedStep, expectsStatus] of setupOwnerExpectations) {
        const owner = document.querySelector('[data-staged-owner="' + ownerName + '"]');
        if (!(owner instanceof HTMLElement)) {
          semanticStructureFailures.push(ownerName + ' setup owner missing');
          continue;
        }
        const header = owner.querySelector(':scope > .setup-owner__header');
        const body = owner.querySelector(':scope > .setup-owner__body');
        const footer = owner.querySelector(':scope > .setup-owner__actions');
        const title = header?.querySelector(':scope > .setup-owner__title');
        const step = header?.querySelector(':scope > .setup-owner__step');
        const status = owner.querySelector(':scope > .setup-status');
        if (!(header instanceof HTMLElement) || !(body instanceof HTMLElement) || !(footer instanceof HTMLElement)
          || !follows(header, body) || !follows(body, footer)) {
          semanticStructureFailures.push(ownerName + ' setup owner hierarchy');
        }
        if (title?.textContent?.trim() !== 'Channel Setup' || step?.textContent?.trim() !== expectedStep) {
          semanticStructureFailures.push(ownerName + ' setup owner title or step');
        }
        if ((status instanceof HTMLElement) !== expectsStatus) {
          semanticStructureFailures.push(ownerName + ' setup owner status scope');
        }
        const labelledBy = owner.getAttribute('aria-labelledby');
        const label = labelledBy === null ? null : document.getElementById(labelledBy);
        if (!(label instanceof HTMLElement) || !owner.contains(label)) {
          semanticStructureFailures.push(ownerName + ' setup owner label reference');
        }
      }
      const libraryOwner = document.querySelector('[data-staged-owner="library"]');
      if (!(libraryOwner instanceof HTMLElement)
        || !(libraryOwner.querySelector(':scope .setup-owner__body > .setup-library-list[data-plex-sections]') instanceof HTMLElement)) {
        semanticStructureFailures.push('library list owner scope');
      }

      const pinModal = document.querySelector('#profile-pin-modal');
      if (!(pinModal instanceof HTMLElement)) {
        semanticStructureFailures.push('profile PIN modal missing');
      } else {
        const pinAvatar = pinModal.querySelector(':scope .profile-pin-user [data-profile-pin-avatar]');
        const pinHeader = pinModal.querySelector(':scope .profile-pin-modal__header');
        const pinSlots = pinModal.querySelectorAll(':scope [data-pin-slot]');
        const pinNumpad = pinModal.querySelector(':scope .profile-pin-modal__numpad');
        const pinButtons = pinNumpad?.querySelectorAll(':scope > button.numpad-btn[data-numpad]') ?? [];
        const pinCancel = pinModal.querySelector(':scope > .profile-pin-modal__dialog > .profile-pin-cancel[data-numpad="cancel"]');
        const focusIds = Array.from(
          pinModal.querySelectorAll('[data-focus-id^="btn-profile-pin-"]'),
          (element) => element.getAttribute('data-focus-id'),
        );
        const expectedFocusIds = new Set([
          'btn-profile-pin-1', 'btn-profile-pin-2', 'btn-profile-pin-3',
          'btn-profile-pin-4', 'btn-profile-pin-5', 'btn-profile-pin-6',
          'btn-profile-pin-7', 'btn-profile-pin-8', 'btn-profile-pin-9',
          'btn-profile-pin-backspace', 'btn-profile-pin-0', 'btn-profile-pin-cancel',
        ]);
        if (!(pinAvatar instanceof HTMLElement) || !(pinHeader instanceof HTMLElement) || !follows(pinAvatar, pinHeader)) {
          semanticStructureFailures.push('profile PIN local header hierarchy');
        }
        if (pinSlots.length !== 4 || pinButtons.length !== 11
          || !(pinCancel instanceof HTMLButtonElement) || pinNumpad?.contains(pinCancel)) {
          semanticStructureFailures.push('profile PIN controls scope');
        }
        if (focusIds.length !== expectedFocusIds.size || new Set(focusIds).size !== focusIds.length
          || focusIds.some((focusId) => focusId === null || !expectedFocusIds.has(focusId))) {
          semanticStructureFailures.push('profile PIN focus ids');
        }
        const labelledBy = pinModal.getAttribute('aria-labelledby');
        const label = labelledBy === null ? null : document.getElementById(labelledBy);
        if (!(label instanceof HTMLElement) || !pinModal.contains(label)) {
          semanticStructureFailures.push('profile PIN label reference');
        }
      }
      if (semanticStructureFailures.length > 0) {
        failures.push('semantic owner structure ' + semanticStructureFailures.join(', '));
      }

      document.dispatchEvent(new KeyboardEvent('keydown', { key: 's', bubbles: true }));
      await new Promise((resolve) => setTimeout(resolve, 0));
      const settingsScreen = document.querySelector('[data-screen="settings"]');
      const settingsSections = document.querySelector('[data-settings-sections]')?.textContent ?? '';
      if (document.documentElement.dataset.activeRoute !== 'settings') failures.push('settings route activation');
      if (!(settingsScreen instanceof HTMLElement) || settingsScreen.hidden) failures.push('settings screen visible');
      if (!settingsSections.includes('Desktop') || /webOS|Luna|Palm/i.test(settingsSections)) {
        failures.push('settings desktop copy');
      }

      ${CHANNEL_BUILDER_FLOW_ASSERTIONS_SOURCE}
      document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));
      document.dispatchEvent(new KeyboardEvent('keyup', { key: 'Escape', bubbles: true }));
      await new Promise((resolve) => setTimeout(resolve, 100));
      if (document.documentElement.dataset.activeRoute !== 'player') {
        document.dispatchEvent(new KeyboardEvent('keydown', { key: 'g', bubbles: true }));
        await new Promise((resolve) => setTimeout(resolve, 0));
        document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));
        document.dispatchEvent(new KeyboardEvent('keyup', { key: 'Escape', bubbles: true }));
        await new Promise((resolve) => setTimeout(resolve, 0));
      }
      const playerScreen = document.querySelector('[data-screen="player"]');
      const playerPresentation = document.querySelector('[data-player-presentation-surface]');
      if (document.documentElement.dataset.activeRoute !== 'player') failures.push('player route activation');
      if (!(playerScreen instanceof HTMLElement) || playerScreen.hidden) failures.push('player screen visible');
      if (!(playerPresentation instanceof HTMLElement) || playerPresentation.tabIndex !== -1) failures.push('player native presentation surface');
      if (!(overlayStack instanceof HTMLElement) || overlayStack.hidden) failures.push('player overlay stack visible');
      if (document.querySelector('.player-quick-actions') !== null) failures.push('obsolete player quick actions');
      if (document.querySelector('[data-overlay-action^="channelDigit"], [data-overlay-action="commitChannelNumber"], [data-overlay-action="clearChannelNumber"]') !== null) failures.push('obsolete channel number proxies');
      for (const required of ['playerOsd', 'nowPlaying', 'miniGuide', 'channelNumber', 'channelBadge', 'playbackOptions', 'transition', 'playerLoading', 'playerError']) {
        if (!(document.querySelector('[data-overlay="' + required + '"]') instanceof HTMLElement)) failures.push('player semantic owner ' + required);
      }
      const reachableCopy = overlayStack instanceof HTMLElement ? overlayStack.textContent ?? '' : '';
      if (/The Midnight Archive|Liminal One|renderer-presentation-player/u.test(reachableCopy)) failures.push('production presentation fixture copy');
      if (
        playerPresentation instanceof HTMLElement &&
        playerScreen instanceof HTMLElement &&
        overlayStack instanceof HTMLElement
      ) {
        const presentationZ = numericZIndex(playerPresentation);
        const screenZ = numericZIndex(playerScreen);
        const overlayZ = numericZIndex(overlayStack);
        if (!(presentationZ < screenZ && screenZ < overlayZ)) {
          failures.push('rd15 z-order ' + JSON.stringify({ presentationZ, screenZ, overlayZ }));
        }
      }
      navigator.permissions?.query?.({ name: 'geolocation' }).catch(() => undefined);

      return { failures };
    })();
  `) as { failures: string[] };

  if (result.failures.length === 0) {
    try {
      await assertFullscreenContinuity(window, result.failures);
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      result.failures.push('fullscreen continuity ' + message);
    }
  }

  await window.webContents.executeJavaScript(`
    window.open('https://example.com');
    true;
  `, true);

  await window.webContents.executeJavaScript(`
    location.assign('https://example.com/disallowed-navigation');
    true;
  `);
  await new Promise((resolve) => setTimeout(resolve, 100));

  if (containmentCounters.navigationDenied < 1) {
    result.failures.push('navigation denial containment');
  }
  if (containmentCounters.windowOpenDenied < 1) {
    result.failures.push('new window containment');
  }
  if (containmentCounters.permissionDenied < 1) {
    result.failures.push('permission containment');
  }
  if (window.webContents.getURL() !== LINEUP_SHELL_URL) {
    result.failures.push('navigation containment');
  }

  if (result.failures.length > 0) {
    throw new Error(`Electron smoke failed: ${result.failures.join(', ')}`);
  }
  await window.loadURL(LINEUP_SHELL_URL);
  const rendererReady = await window.webContents.executeJavaScript(`
    new Promise((resolve) => {
      const deadline = performance.now() + 3000;
      const poll = () => {
        if (document.documentElement.dataset.shellBoot === 'ready') {
          resolve(true);
          return;
        }
        if (performance.now() >= deadline) {
          resolve(false);
          return;
        }
        setTimeout(poll, 20);
      };
      poll();
    });
  `) as boolean;
  if (!rendererReady) {
    throw new Error('Electron smoke failed: renderer boot readiness timeout');
  }
  await window.webContents.executeJavaScript(`
    (async () => {
      if (document.documentElement.dataset.activeRoute !== 'channelSetup') return;
      document.dispatchEvent(new KeyboardEvent('keydown', { key: 's', bubbles: true }));
      await new Promise((resolve) => setTimeout(resolve, 0));
      document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));
      document.dispatchEvent(new KeyboardEvent('keyup', { key: 'Escape', bubbles: true }));
      await new Promise((resolve) => setTimeout(resolve, 0));
    })();
  `);
  await assertRendererCloseLifecycle(window, result.failures);
  if (result.failures.length > 0) {
    throw new Error(`Electron smoke failed: ${result.failures.join(', ')}`);
  }
  console.warn('Electron smoke verification passed.');
}
