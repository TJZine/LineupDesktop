import type { PlexHomeUserSummary } from '../contracts/plex.js';
import type { FocusRegistry, FocusState } from './navigation.js';

export interface ProfilePinModalContext {
  getPlexController: () => {
    setHomeUserPin: (pin: string) => void;
    switchHomeUser: (userId: string) => Promise<void>;
    getState: () => { errorText: string | null };
    invalidateProfileSwitch: () => void;
  };
  getFocusState: () => FocusState;
  setFocusState: (state: FocusState) => void;
  getFocusRegistry: () => FocusRegistry;
  renderApp: () => void;
  onProfileSelected?: () => void;
}

let activePinHomeUser: PlexHomeUserSummary | null = null;
let enteredPin = '';
let context: ProfilePinModalContext | null = null;
let isSubmitting = false;
let submissionGeneration = 0;
let keydownListener: ((event: KeyboardEvent) => void) | null = null;
let invokingFocusId: string | null = null;
let lastActivatedFocusId = 'btn-profile-pin-5';

export function initializeProfilePinModal(ctx: ProfilePinModalContext): void {
  context = ctx;

  document.getElementById('profile-pin-modal')?.addEventListener('click', (event) => {
    if (isSubmitting) return;
    if (!(event.target instanceof HTMLElement)) return;
    const numpadBtn = event.target.closest<HTMLButtonElement>('[data-numpad]');
    if (numpadBtn) {
      const val = numpadBtn.dataset.numpad;
      if (val) {
        handleNumpadInput(val, numpadBtn.dataset.focusId);
      }
    }
  });
}

export function isProfilePinModalActive(): boolean {
  return activePinHomeUser !== null;
}

export function getActivePinHomeUser(): PlexHomeUserSummary | null {
  return activePinHomeUser;
}

export function openProfilePinModal(user: PlexHomeUserSummary): void {
  if (!context) return;
  submissionGeneration += 1;
  activePinHomeUser = user;
  invokingFocusId = context.getFocusState().activeId;
  enteredPin = '';
  isSubmitting = false;
  lastActivatedFocusId = 'btn-profile-pin-5';

  const modal = document.getElementById('profile-pin-modal');
  if (modal) {
    modal.hidden = false;
    modal.setAttribute('aria-hidden', 'false');
  }

  const nameEl = document.getElementById('profile-pin-modal-username');
  if (nameEl) {
    nameEl.textContent = user.title;
  }
  const avatarEl = document.querySelector<HTMLElement>('[data-profile-pin-avatar]');
  if (avatarEl) {
    avatarEl.textContent = user.title.slice(0, 1).toUpperCase();
  }
  updatePinSlotsDisplay();
  const errorEl = document.getElementById('profile-pin-modal-error');
  if (errorEl) {
    errorEl.hidden = true;
  }

  const numpadButtons = Array.from(document.querySelectorAll<HTMLButtonElement>('[data-numpad]'));
  for (const button of numpadButtons) {
    button.disabled = false;
  }

  // Register keydown listener when active
  if (!keydownListener) {
    keydownListener = (event: KeyboardEvent) => {
      if (isSubmitting) return;
      if (event.key >= '0' && event.key <= '9') {
        event.preventDefault();
        event.stopPropagation();
        handleNumpadInput(event.key, `btn-profile-pin-${event.key}`);
      } else if (event.key === 'Backspace') {
        event.preventDefault();
        event.stopPropagation();
        handleNumpadInput('backspace', 'btn-profile-pin-backspace');
      } else if (event.key === 'Delete') {
        event.preventDefault();
        event.stopPropagation();
        handleNumpadInput('backspace', 'btn-profile-pin-backspace');
      } else if (event.key === 'Escape') {
        event.preventDefault();
        event.stopPropagation();
        handleNumpadInput('cancel', 'btn-profile-pin-cancel');
      }
    };
    window.addEventListener('keydown', keydownListener, { capture: true });
  }

  context.renderApp();
  const focusRegistry = context.getFocusRegistry();
  const focusState = context.getFocusState();
  context.setFocusState(focusRegistry.focusTarget(focusState, 'btn-profile-pin-5').state);
  context.renderApp();
}

function updatePinSlotsDisplay(): void {
  for (let i = 0; i < 4; i++) {
    const slot = document.querySelector(`[data-pin-slot="${i}"]`);
    if (slot) {
      slot.textContent = enteredPin.length > i ? '●' : '';
      slot.classList.toggle('filled', enteredPin.length > i);
    }
  }
}

function handleNumpadInput(value: string, focusId?: string): void {
  if (focusId) lastActivatedFocusId = focusId;
  if (value === 'cancel') {
    closeProfilePinModal();
  } else if (value === 'backspace') {
    if (enteredPin.length > 0) {
      enteredPin = enteredPin.slice(0, -1);
      updatePinSlotsDisplay();
    }
    const errorEl = document.getElementById('profile-pin-modal-error');
    if (errorEl) errorEl.hidden = true;
  } else if (value >= '0' && value <= '9') {
    if (enteredPin.length < 4 && !isSubmitting) {
      enteredPin += value;
      updatePinSlotsDisplay();
      if (enteredPin.length === 4) {
        void submitProfilePin();
      }
    }
  }
}

async function submitProfilePin(): Promise<void> {
  if (!activePinHomeUser || !context || isSubmitting) return;
  const generation = submissionGeneration;
  const submissionContext = context;
  isSubmitting = true;
  const numpadButtons = Array.from(document.querySelectorAll<HTMLButtonElement>('[data-numpad]'));
  for (const button of numpadButtons) {
    button.disabled = true;
  }

  const controller = submissionContext.getPlexController();
  controller.setHomeUserPin(enteredPin);
  const userId = activePinHomeUser.id;
  try {
    await controller.switchHomeUser(userId);
  } finally {
    if (generation === submissionGeneration && context === submissionContext) {
      isSubmitting = false;
    }
  }

  if (generation !== submissionGeneration || context !== submissionContext) return;

  const plexState = controller.getState();
  if (plexState.errorText !== null) {
    for (const button of numpadButtons) {
      button.disabled = false;
    }
    const errorEl = document.getElementById('profile-pin-modal-error');
    if (errorEl) {
      errorEl.textContent = plexState.errorText;
      errorEl.hidden = false;
    }
    enteredPin = '';
    updatePinSlotsDisplay();
    const focusRegistry = submissionContext.getFocusRegistry();
    submissionContext.setFocusState(
      focusRegistry.focusTarget(submissionContext.getFocusState(), lastActivatedFocusId).state,
    );
    submissionContext.renderApp();
  } else {
    closeProfilePinModal({ refocus: false, invalidate: false });
    submissionContext.onProfileSelected?.();
  }
}

export function closeProfilePinModal(options?: { refocus?: boolean; invalidate?: boolean }): void {
  if (!context) return;
  submissionGeneration += 1;
  isSubmitting = false;

  if (options?.invalidate !== false && activePinHomeUser !== null) {
    context.getPlexController().invalidateProfileSwitch();
  }

  const modal = document.getElementById('profile-pin-modal');
  if (modal) {
    modal.hidden = true;
    modal.setAttribute('aria-hidden', 'true');
  }

  if (keydownListener) {
    window.removeEventListener('keydown', keydownListener, { capture: true });
    keydownListener = null;
  }

  if (options?.refocus !== false) {
    const focusRegistry = context.getFocusRegistry();
    let focusState = context.getFocusState();
    if (invokingFocusId !== null) {
      focusState = focusRegistry.focusTarget(focusState, invokingFocusId).state;
    } else {
      focusState = focusRegistry.focusRoute(focusState, 'channelSetup').state;
    }
    context.setFocusState(focusState);
  }

  activePinHomeUser = null;
  enteredPin = '';
  invokingFocusId = null;
  context.renderApp();
}
