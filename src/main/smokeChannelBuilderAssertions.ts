export const CHANNEL_BUILDER_BRIDGE_ASSERTIONS_SOURCE = String.raw`
      {
        const channelSetupApi = bridge?.channelSetup;
        const expectedMethods = ['getStatus', 'startReview', 'startApply', 'getOperation', 'cancel'];
        if (!channelSetupApi || typeof channelSetupApi !== 'object') {
          failures.push('channelSetup api');
        } else {
          const actualMethods = Object.keys(channelSetupApi).sort();
          if (JSON.stringify(actualMethods) !== JSON.stringify([...expectedMethods].sort())) {
            failures.push('channelSetup exact api methods ' + JSON.stringify(actualMethods));
          }
          for (const method of expectedMethods) {
            if (typeof channelSetupApi[method] !== 'function') {
              failures.push('channelSetup api method ' + method);
            }
          }
          if ('commit' in channelSetupApi) failures.push('legacy channelSetup commit method');
        }

      }
`;

export const CHANNEL_BUILDER_FLOW_ASSERTIONS_SOURCE = String.raw`
      {
        const setupButton = document.querySelector('[data-focus-id="settings-open-channel-setup"]');
        if (!(setupButton instanceof HTMLButtonElement)) {
          failures.push('channel setup pointer action');
        } else {
          setupButton.click();
        }
        const setupScreen = document.querySelector('[data-screen="channelSetup"]');
        if (document.documentElement.dataset.activeRoute !== 'channelSetup') {
          failures.push('channel setup route activation');
        }
        if (!(setupScreen instanceof HTMLElement) || setupScreen.hidden) {
          failures.push('channel setup screen visible');
        }
        if (document.querySelector('[data-channel-commit-action]') !== null) {
          failures.push('legacy channel commit selector');
        }
        const buildConfirm = document.querySelector('[data-setup-flow-action="buildConfirm"]');
        if (buildConfirm instanceof HTMLButtonElement && !buildConfirm.disabled) {
          buildConfirm.click();
          await new Promise((resolve) => setTimeout(resolve, 50));
        }
        const setupText = setupScreen instanceof HTMLElement ? setupScreen.textContent ?? '' : '';
        const plexRuntimePanel = document.querySelector('[data-plex-runtime-panel]');
        const onboardingHost = document.querySelector('[data-onboarding-host]');
        const onboardingReady = onboardingHost instanceof HTMLElement
          && !onboardingHost.hidden && setupText.includes('Sign in to Plex')
          && document.querySelector('[data-focus-id="btn-auth-request"]') instanceof HTMLButtonElement;
        const stagedSetupReady = plexRuntimePanel instanceof HTMLElement
          && document.querySelector('.setup-rail') instanceof HTMLElement
          && document.querySelector('.setup-detail-pane') instanceof HTMLElement
          && document.querySelectorAll('[data-setup-stage]').length >= 5
          && document.querySelectorAll('[data-setup-section]').length >= 5
          && setupText.includes('Plex setup')
          && setupText.includes('Build channels')
          && getComputedStyle(setupScreen).overflowY === 'auto';
        if (!onboardingReady && !stagedSetupReady) {
          failures.push('channel setup plex flow content');
        }
      }
`;
