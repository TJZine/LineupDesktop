import type { ShellStatusEvent } from '../contracts/shell.js';

const statusElement = document.querySelector<HTMLElement>('[data-shell-status]');
const capabilitiesElement = document.querySelector<HTMLElement>('[data-shell-capabilities]');
const fullscreenButton = document.querySelector<HTMLButtonElement>('[data-fullscreen-toggle]');

let fullscreenEnabled = false;

function renderStatus(event: ShellStatusEvent): void {
  if (statusElement) {
    statusElement.textContent = `${event.status} ${new Date(event.timestampMs).toISOString()}`;
  }
}

window.lineupDesktop.shell.onStatusChanged(renderStatus);

const capabilities = await window.lineupDesktop.shell.getCapabilities();
if (capabilitiesElement) {
  capabilitiesElement.textContent = capabilities.ok
    ? `${capabilities.value.appName} ${capabilities.value.appVersion} ${capabilities.value.shellMode}`
    : capabilities.error.message;
}

fullscreenButton?.addEventListener('click', async () => {
  const result = await window.lineupDesktop.window.setFullscreen(!fullscreenEnabled);
  if (result.ok) {
    fullscreenEnabled = result.value.enabled;
    fullscreenButton.setAttribute('aria-pressed', String(fullscreenEnabled));
  }
});

document.documentElement.dataset.shellBoot = 'ready';
