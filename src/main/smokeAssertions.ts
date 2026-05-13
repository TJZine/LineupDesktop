import type { BrowserWindow } from 'electron';

import { LINEUP_SHELL_URL } from '../contracts/shell.js';
import { LINEUP_CSP } from './protocol.js';
import { assertFullscreenContinuity } from './smokeFullscreenAssertions.js';

export interface ShellContainmentCounters {
  navigationDenied: number;
  windowOpenDenied: number;
  permissionDenied: number;
  webviewDenied: number;
}

export async function runSmokeAssertions(
  window: BrowserWindow,
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
      try {
        Function('return 1')();
        failures.push('csp unsafe eval');
      } catch {}
      const rootStyle = getComputedStyle(document.documentElement);
      const appShell = document.querySelector('[data-style-surface="app-shell"]');
      const routeRail = document.querySelector('[data-style-surface="route-rail"]');
      const screenRoot = document.querySelector('[data-static-screen-root]');
      const screenStack = document.querySelector('[data-static-screens-mounted]');
      const styledPlayerScreen = document.querySelector('[data-screen="player"]');
      const playerSurface = document.querySelector('.player-surface');
      const playerRouteButton = document.querySelector('[data-route-button="player"]');
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
      if (!(routeRail instanceof HTMLElement) || getComputedStyle(routeRail).gridArea !== 'rail') {
        failures.push('route rail style loaded');
      }
      if (
        !(styledPlayerScreen instanceof HTMLElement) ||
        getComputedStyle(styledPlayerScreen).borderRadius !== '8px'
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
      if (!(playerRouteButton instanceof HTMLButtonElement)) {
        failures.push('focus style target');
      } else {
        playerRouteButton.classList.add('is-focused');
        const focusStyle = getComputedStyle(playerRouteButton);
        if (focusStyle.outlineStyle !== 'solid' || focusStyle.outlineWidth !== '3px') {
          failures.push('focus style loaded');
        }
        playerRouteButton.classList.remove('is-focused');
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
      if (!bridge?.player?.onEvent) failures.push('player event api');
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
                actual:
                  topElement instanceof HTMLElement
                    ? topElement.getAttribute('data-overlay') ?? topElement.className
                    : null,
              }),
          );
        }
      };
      const rectsOverlap = (left, right) => {
        const leftRect = left.getBoundingClientRect();
        const rightRect = right.getBoundingClientRect();
        return (
          leftRect.left < rightRect.right &&
          leftRect.right > rightRect.left &&
          leftRect.top < rightRect.bottom &&
          leftRect.bottom > rightRect.top
        );
      };
      const guideButton = document.querySelector('[data-route-button="guide"]');
      if (!(guideButton instanceof HTMLButtonElement)) {
        failures.push('guide route button');
      } else {
        guideButton.click();
      }
      const guideScreen = document.querySelector('[data-screen="guide"]');
      const guideGrid = document.querySelector('[data-epg-grid]');
      const guideActions = Array.from(document.querySelectorAll('[data-epg-action]'));
      const overlayStack = document.querySelector('[data-overlay-stack]');
      const offRouteOverlayAction = document.querySelector('[data-overlay-action="openMiniGuide"]');
      const detailChannel = document.querySelector('[data-epg-detail-channel]')?.textContent ?? '';
      const detailTitle = document.querySelector('[data-epg-detail-title]')?.textContent ?? '';
      const detailTime = document.querySelector('[data-epg-detail-time]')?.textContent ?? '';
      const guideGridText = guideGrid?.textContent ?? '';
      if (document.documentElement.dataset.activeRoute !== 'guide') failures.push('guide route activation');
      if (!(guideScreen instanceof HTMLElement) || guideScreen.hidden) failures.push('guide screen visible');
      if (!(overlayStack instanceof HTMLElement) || !overlayStack.hidden) failures.push('guide overlay stack hidden');
      if (overlayStack instanceof HTMLElement && overlayStack.getAttribute('aria-hidden') !== 'true') {
        failures.push('guide overlay stack aria hidden');
      }
      if (!(offRouteOverlayAction instanceof HTMLButtonElement) || !offRouteOverlayAction.disabled) {
        failures.push('off-route overlay action disabled');
      }
      if (document.documentElement.dataset.activeOverlay !== '') failures.push('off-route active overlay');
      if (!detailChannel.includes('101 Liminal One')) failures.push('guide detail channel ' + detailChannel);
      if (detailTitle !== 'The Midnight Archive') failures.push('guide detail title ' + detailTitle);
      if (detailTime !== 'Signal Lost - 8:30 PM - 9:30 PM') failures.push('guide detail time ' + detailTime);
      if (!guideGridText.includes('8:00 PM') || !guideGridText.includes('The Midnight Archive')) {
        failures.push('guide grid fake data');
      }
      if (guideActions.length !== 6) failures.push('guide actions ' + guideActions.length);

      const settingsButton = document.querySelector('[data-route-button="settings"]');
      if (!(settingsButton instanceof HTMLButtonElement)) {
        failures.push('settings route button');
      } else {
        settingsButton.click();
      }
      const settingsScreen = document.querySelector('[data-screen="settings"]');
      const settingsSections = document.querySelector('[data-settings-sections]')?.textContent ?? '';
      if (document.documentElement.dataset.activeRoute !== 'settings') failures.push('settings route activation');
      if (!(settingsScreen instanceof HTMLElement) || settingsScreen.hidden) failures.push('settings screen visible');
      if (!settingsSections.includes('Desktop') || /webOS|Luna|Palm/i.test(settingsSections)) {
        failures.push('settings desktop copy');
      }

      const setupButton = document.querySelector('[data-route-button="channelSetup"]');
      if (!(setupButton instanceof HTMLButtonElement)) {
        failures.push('channel setup route button');
      } else {
        setupButton.click();
      }
      const setupScreen = document.querySelector('[data-screen="channelSetup"]');
      const setupSteps = document.querySelector('[data-setup-steps]')?.textContent ?? '';
      const setupValidation = document.querySelector('[data-setup-validation]')?.textContent ?? '';
      if (document.documentElement.dataset.activeRoute !== 'channelSetup') {
        failures.push('channel setup route activation');
      }
      if (!(setupScreen instanceof HTMLElement) || setupScreen.hidden) failures.push('channel setup screen visible');
      if (!setupSteps.includes('Arrange channels') || !setupValidation.includes('Draft setup')) {
        failures.push('channel setup workflow content');
      }

      const playerButton = document.querySelector('[data-route-button="player"]');
      if (!(playerButton instanceof HTMLButtonElement)) {
        failures.push('player route button');
      } else {
        playerButton.click();
      }
      const playerScreen = document.querySelector('[data-screen="player"]');
      const playerPresentation = document.querySelector('[data-player-presentation-surface]');
      const osdOverlay = document.querySelector('[data-overlay="playerOsd"]');
      const nowPlayingTitle = document.querySelector('[data-overlay-now-playing-title]')?.textContent ?? '';
      const miniGuideButton = document.querySelector('[data-overlay-action="openMiniGuide"]');
      if (!(miniGuideButton instanceof HTMLButtonElement)) {
        failures.push('mini guide action');
      } else {
        miniGuideButton.click();
      }
      const miniGuideOverlay = document.querySelector('[data-overlay="miniGuide"]');
      const miniGuideText = document.querySelector('[data-overlay-mini-guide]')?.textContent ?? '';
      const channelNumberButton = document.querySelector('[data-overlay-action="channelDigit4"]');
      if (!(channelNumberButton instanceof HTMLButtonElement)) {
        failures.push('channel number action');
      } else {
        channelNumberButton.click();
      }
      const channelNumberOverlay = document.querySelector('[data-overlay="channelNumber"]');
      const channelNumberValue = document.querySelector('[data-overlay-channel-number-value]')?.textContent ?? '';
      if (document.documentElement.dataset.activeRoute !== 'player') failures.push('player route activation');
      if (!(playerScreen instanceof HTMLElement) || playerScreen.hidden) failures.push('player screen visible');
      if (!(osdOverlay instanceof HTMLElement) || osdOverlay.hidden) failures.push('OSD visible');
      if (!(playerPresentation instanceof HTMLElement)) failures.push('player presentation surface');
      if (!(overlayStack instanceof HTMLElement) || overlayStack.hidden) failures.push('player overlay stack visible');
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
      if (nowPlayingTitle !== 'The Midnight Archive') failures.push('now playing title ' + nowPlayingTitle);
      if (!(miniGuideOverlay instanceof HTMLElement) || miniGuideOverlay.hidden) failures.push('mini guide visible');
      assertTopElementAtCenter(miniGuideOverlay, 'mini guide z-order');
      if (!miniGuideText.includes('101') || !miniGuideText.includes('The Midnight Archive')) {
        failures.push('mini guide fake data');
      }
      if (!(channelNumberOverlay instanceof HTMLElement) || channelNumberOverlay.hidden) {
        failures.push('channel number visible');
      }
      assertTopElementAtCenter(channelNumberOverlay, 'channel number z-order');
      if (channelNumberValue !== '4--') failures.push('channel number value ' + channelNumberValue);
      const nowPlayingOverlay = document.querySelector('[data-overlay="nowPlaying"]');
      if (
        osdOverlay instanceof HTMLElement &&
        nowPlayingOverlay instanceof HTMLElement &&
        rectsOverlap(osdOverlay, nowPlayingOverlay)
      ) {
        failures.push('OSD now-playing incoherent overlap');
      }

      const closeOverlayButton = document.querySelector('[data-overlay-action="closeTopOverlay"]');
      const playerOsdButton = document.querySelector('[data-focus-id="player-osd"]');
      if (!(closeOverlayButton instanceof HTMLButtonElement)) {
        failures.push('close overlay action');
      } else {
        closeOverlayButton.click();
        closeOverlayButton.click();
        closeOverlayButton.click();
      }
      if (
        !(playerOsdButton instanceof HTMLButtonElement) ||
        document.activeElement !== playerOsdButton ||
        playerOsdButton.tabIndex !== 0
      ) {
        failures.push(
          'overlay focus fallback ' +
            JSON.stringify({
              activeFocus:
                document.activeElement instanceof HTMLElement
                  ? document.activeElement.dataset.focusId ?? ''
                  : '',
              playerOsdTabIndex:
                playerOsdButton instanceof HTMLButtonElement ? playerOsdButton.tabIndex : null,
            }),
        );
      }

      window.open('https://example.com');
      navigator.permissions?.query?.({ name: 'geolocation' }).catch(() => undefined);

      return { failures };
    })();
  `) as { failures: string[] };

  if (result.failures.length === 0) {
    await assertFullscreenContinuity(window, result.failures);
  }

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
  console.warn('Electron smoke verification passed.');
}
