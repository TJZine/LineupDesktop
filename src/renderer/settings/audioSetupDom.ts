import type { AudioSetupState } from './audioSetupRuntime.js';

export function renderAudioSetupDom(state: AudioSetupState, documentRef: Document): void {
  const list = documentRef.querySelector<HTMLElement>('[data-audio-setup-outputs]');
  const status = documentRef.querySelector<HTMLElement>('[data-audio-setup-status]');
  const complete = documentRef.querySelector<HTMLButtonElement>('[data-audio-setup-action="complete"]');
  if (status !== null) status.textContent = state.message;
  if (complete !== null) {
    complete.disabled = state.status === 'loading' || state.status === 'saving';
    complete.setAttribute('aria-busy', String(state.status === 'saving'));
    complete.textContent = state.status === 'saving' ? 'Saving…' : 'Use selected output';
  }
  list?.replaceChildren(...state.outputs.map((output) => {
    const button = documentRef.createElement('button');
    button.type = 'button';
    button.className = 'audio-output-row';
    button.dataset.audioOutputId = output.id;
    button.dataset.focusId = `audio-output-${output.id}`;
    button.setAttribute('aria-pressed', String(output.id === state.selectedId));
    button.disabled = state.status === 'loading' || state.status === 'saving';
    const label = documentRef.createElement('strong');
    label.textContent = output.kind === 'system-default' ? 'Use System default' : output.label;
    const detail = documentRef.createElement('span');
    detail.textContent = output.kind === 'system-default'
      ? 'Uses the operating system default audio output.'
      : 'Renderer-safe audio output';
    button.append(label, detail);
    return button;
  }));
}
