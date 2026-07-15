export const GUIDE_SMOKE_ASSERTIONS_SOURCE = String.raw`
      const readGuideSmokeState = () => {
        const guideScreen = document.querySelector('[data-screen="guide"]');
        const guideGrid = document.querySelector('[data-epg-grid]');
        const legacyGuideActions = Array.from(document.querySelectorAll('[data-epg-action]'));
        const guideProgramActions = Array.from(guideGrid?.querySelectorAll('[data-guide-program-action]') ?? []);
        const guideStateActions = Array.from(guideGrid?.querySelectorAll('[data-guide-action]') ?? []);
        const guidePresentationState = guideGrid?.querySelector('[data-epg-state]')?.dataset.epgState ?? '';
        const selectedGuideProgram = guideProgramActions.find(
          (element) => element.dataset.selectedProgram === 'true',
        );
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
          normalizedGuideText.includes('No programs in this window') ||
          normalizedGuideText.includes('Guide unavailable');
        const guideShowsScheduleDetails =
          guideGridText.trim().length >= 12 &&
          detailTitle.trim().length > 0 &&
          detailChannel.trim().length > 0 &&
          detailTime.trim().length > 0;
        const guideProgramControlsAreSafe =
          guideProgramActions.length > 0 &&
          guideProgramActions.every((element) =>
            element instanceof HTMLButtonElement &&
            typeof element.dataset.focusId === 'string' &&
            element.dataset.focusId.startsWith('guide-program-') &&
            typeof element.dataset.guideChannelId === 'string' &&
            element.dataset.guideChannelId.length > 0 &&
            typeof element.dataset.guideProgramId === 'string' &&
            element.dataset.guideProgramId.length > 0 &&
            /^\d+$/.test(element.dataset.guideGeneration ?? '')
          ) &&
          selectedGuideProgram instanceof HTMLButtonElement &&
          selectedGuideProgram.textContent?.includes(detailTitle.trim()) === true;
        const authorizedStateActions = {
          loading: ['back'],
          'empty-channels': ['setup', 'back'],
          'empty-programs': ['refresh', 'setup', 'back'],
          error: ['retry', 'back'],
        }[guidePresentationState];
        const guideStateActionsMatch =
          authorizedStateActions !== undefined &&
          guideProgramActions.length === 0 &&
          guideStateActions.length === authorizedStateActions.length &&
          guideStateActions.every(
            (element, index) =>
              element instanceof HTMLButtonElement &&
              element.dataset.guideAction === authorizedStateActions[index] &&
              element.dataset.focusId === 'guide-state-' + authorizedStateActions[index],
          );
        const guideStateSemanticsValid = guidePresentationState === 'ready'
          ? guideShowsScheduleDetails && guideProgramControlsAreSafe && guideStateActions.length === 0
          : guideStateActionsMatch;
        return {
          guideScreen,
          guideGrid,
          legacyGuideActions,
          guideProgramActions,
          guideStateActions,
          guidePresentationState,
          guideProgramControlsAreSafe,
          guideStateActionsMatch,
          guideStateSemanticsValid,
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
        !guideState.guideStateSemanticsValid
      ) {
        await new Promise((resolve) => setTimeout(resolve, 50));
        guideState = readGuideSmokeState();
      }
      const {
        guideScreen,
        guideGrid,
        legacyGuideActions,
        guideProgramActions,
        guideStateActions,
        guidePresentationState,
        guideProgramControlsAreSafe,
        guideStateActionsMatch,
        guideStateSemanticsValid,
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
        guideStateActionsMatch && (
          guidePresentationState === 'loading' ||
          (expectedEmptyGuideState && guidePresentationState === 'empty-channels') ||
          guidePresentationState === 'empty-programs' ||
          (runtimeIndicatesUnavailable && guidePresentationState === 'error')
        );
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
              guidePresentationState,
              guideProgramControlsAreSafe,
              guideStateActionsMatch,
              guideStateSemanticsValid,
              expectedEmptyGuideState,
              runtimeIndicatesUnavailable,
            }),
        );
      }
      if (!guideShowsAuthorizedSafeState && !guideShowsScheduleDetails) {
        failures.push('guide grid content ' + JSON.stringify({ guideGridText }));
      }
      if (!guideStateSemanticsValid) {
        failures.push(
          'guide action semantics ' +
            JSON.stringify({
              guidePresentationState,
              legacyGuideActionCount: legacyGuideActions.length,
              guideProgramActionCount: guideProgramActions.length,
              guideStateActions: guideStateActions.map((element) => element.dataset.guideAction ?? ''),
              guideProgramControlsAreSafe,
              guideStateActionsMatch,
            }),
        );
      }
      if (legacyGuideActions.length !== 0) failures.push('legacy guide actions ' + legacyGuideActions.length);
`;
