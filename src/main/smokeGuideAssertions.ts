export const GUIDE_SMOKE_ASSERTIONS_SOURCE = String.raw`
      const readGuideSmokeState = () => {
        const guideScreen = document.querySelector('[data-screen="guide"]');
        const guideGrid = document.querySelector('[data-epg-grid]');
        const guideActions = Array.from(document.querySelectorAll('[data-epg-action]'));
        const overlayStack = document.querySelector('[data-overlay-stack]');
        const offRouteOverlayAction = document.querySelector('[data-overlay-action="openMiniGuide"]');
        const detailChannel = document.querySelector('[data-epg-detail-channel]')?.textContent ?? '';
        const detailTitle = document.querySelector('[data-epg-detail-title]')?.textContent ?? '';
        const detailTime = document.querySelector('[data-epg-detail-time]')?.textContent ?? '';
        const guideGridText = guideGrid?.textContent ?? '';
        const normalizedGuideText = [detailChannel, detailTitle, detailTime, guideGridText].join(' ').replace(/\s+/g, ' ').trim();
        const guideShowsPlaceholderState =
          normalizedGuideText.includes('Loading guide') ||
          normalizedGuideText.includes('Schedule rows are preparing') ||
          normalizedGuideText.includes('Guide ready') ||
          normalizedGuideText.includes('No channels available') ||
          normalizedGuideText.includes('Guide unavailable');
        const guideShowsScheduleDetails =
          guideGridText.trim().length >= 12 &&
          detailTitle.trim().length > 0 &&
          detailChannel.trim().length > 0 &&
          detailTime.trim().length > 0;
        return {
          guideScreen,
          guideGrid,
          guideActions,
          overlayStack,
          offRouteOverlayAction,
          detailChannel,
          detailTitle,
          detailTime,
          guideGridText,
          normalizedGuideText,
          guideShowsPlaceholderState,
          guideShowsScheduleDetails,
        };
      };
      const guideButton = document.querySelector('[data-route-button="guide"]');
      if (!(guideButton instanceof HTMLButtonElement)) {
        failures.push('guide route button');
      } else {
        guideButton.click();
      }
      let guideRuntimeResult;
      try {
        guideRuntimeResult = await bridge.guide.getPresentation({
          startTimeMs: Date.now(),
          durationMs: 30 * 60 * 1000,
        });
      } catch (error) {
        guideRuntimeResult = {
          ok: false,
          error: {
            message: error instanceof Error ? error.message : String(error),
          },
        };
      }
      const expectedEmptyGuideState =
        guideRuntimeResult.ok &&
        Array.isArray(guideRuntimeResult.value?.channels) &&
        guideRuntimeResult.value.channels.length === 0;
      const runtimeIndicatesUnavailable = !guideRuntimeResult.ok;
      const guideDeadlineMs = performance.now() + 1500;
      let guideState = readGuideSmokeState();
      while (
        performance.now() < guideDeadlineMs &&
        !guideState.guideShowsScheduleDetails &&
        !(expectedEmptyGuideState && guideState.normalizedGuideText.includes('No channels available')) &&
        !(runtimeIndicatesUnavailable && guideState.normalizedGuideText.includes('Guide unavailable'))
      ) {
        await new Promise((resolve) => setTimeout(resolve, 50));
        guideState = readGuideSmokeState();
      }
      const {
        guideScreen,
        guideGrid,
        guideActions,
        overlayStack,
        offRouteOverlayAction,
        detailChannel,
        detailTitle,
        detailTime,
        guideGridText,
        normalizedGuideText,
        guideShowsPlaceholderState,
        guideShowsScheduleDetails,
      } = guideState;
      const guideShowsAuthorizedSafeState =
        (expectedEmptyGuideState && normalizedGuideText.includes('No channels available')) ||
        (runtimeIndicatesUnavailable && normalizedGuideText.includes('Guide unavailable'));
      const guideShowsMeaningfulDetails =
        (guideShowsScheduleDetails || guideShowsAuthorizedSafeState) &&
        !/undefined|null|NaN/i.test(normalizedGuideText);
      if (document.documentElement.dataset.activeRoute !== 'guide') failures.push('guide route activation');
      if (!(guideScreen instanceof HTMLElement) || guideScreen.hidden) failures.push('guide screen visible');
      if (!(guideGrid instanceof HTMLElement)) failures.push('guide grid target');
      if (!(overlayStack instanceof HTMLElement) || !overlayStack.hidden) failures.push('guide overlay stack hidden');
      if (overlayStack instanceof HTMLElement && overlayStack.getAttribute('aria-hidden') !== 'true') {
        failures.push('guide overlay stack aria hidden');
      }
      if (!(offRouteOverlayAction instanceof HTMLButtonElement) || !offRouteOverlayAction.disabled) {
        failures.push('off-route overlay action disabled');
      }
      if (document.documentElement.dataset.activeOverlay !== '') failures.push('off-route active overlay');
      if (!guideShowsMeaningfulDetails) {
        failures.push(
          'guide runtime content ' +
            JSON.stringify({
              detailChannel,
              detailTitle,
              detailTime,
              guideGridText: guideGridText.slice(0, 240),
              guideShowsPlaceholderState,
              guideShowsScheduleDetails,
              guideShowsMeaningfulDetails,
              expectedEmptyGuideState,
              runtimeIndicatesUnavailable,
            }),
        );
      }
      if (!guideShowsAuthorizedSafeState && !guideShowsScheduleDetails) {
        failures.push('guide grid content ' + JSON.stringify({ guideGridText }));
      }
      if (guideActions.length !== 6) failures.push('guide actions ' + guideActions.length);
`;
