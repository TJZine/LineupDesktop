import type { PlexHomeUserSummary } from '../contracts/plex.js';
import type { FocusRegistry, FocusState } from './navigation.js';

export interface ProfilePinModalContext {
  getPlexController: () => {
    setHomeUserPin: (pin: string) => void;
    switchHomeUser: (userId: string) => Promise<void>;
    getState: () => { errorText: string | null };
  };
  getFocusState: () => FocusState;
  setFocusState: (state: FocusState) => void;
  getFocusRegistry: () => FocusRegistry;
  renderApp: () => void;
}

let activePinHomeUser: PlexHomeUserSummary | null = null;
let enteredPin = '';
let context: ProfilePinModalContext | null = null;
let isSubmitting = false;
let keydownListener: ((event: KeyboardEvent) => void) | null = null;

export function initializeProfilePinModal(ctx: ProfilePinModalContext): void {
  context = ctx;

  document.getElementById('profile-pin-modal')?.addEventListener('click', (event) => {
    if (isSubmitting) return;
    if (!(event.target instanceof HTMLElement)) return;
    const numpadBtn = event.target.closest<HTMLButtonElement>('.numpad-btn');
    if (numpadBtn) {
      const val = numpadBtn.dataset.numpad;
      if (val) {
        handleNumpadInput(val);
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
  activePinHomeUser = user;
  enteredPin = '';
  isSubmitting = false;

  const modal = document.getElementById('profile-pin-modal');
  if (modal) {
    modal.hidden = false;
    modal.setAttribute('aria-hidden', 'false');
  }

  const nameEl = document.getElementById('profile-pin-modal-username');
  if (nameEl) {
    nameEl.textContent = user.title;
  }
  updatePinSlotsDisplay();
  const errorEl = document.getElementById('profile-pin-modal-error');
  if (errorEl) {
    errorEl.hidden = true;
  }

  const numpadButtons = Array.from(document.querySelectorAll<HTMLButtonElement>('.numpad-btn'));
  for (const button of numpadButtons) {
    button.disabled = false;
  }

  // Register keydown listener when active
  if (!keydownListener) {
    keydownListener = (event: KeyboardEvent) => {
      if (isSubmitting) return;
      if (event.key >= '0' && event.key <= '9') {
        handleNumpadInput(event.key);
        event.preventDefault();
        event.stopPropagation();
      } else if (event.key === 'Backspace') {
        handleNumpadInput('backspace');
        event.preventDefault();
        event.stopPropagation();
      } else if (event.key === 'Escape') {
        handleNumpadInput('cancel');
        event.preventDefault();
        event.stopPropagation();
      }
    };
    window.addEventListener('keydown', keydownListener, { capture: true });
  }

  const focusRegistry = context.getFocusRegistry();
  const focusState = context.getFocusState();
  context.setFocusState(focusRegistry.focusTarget(focusState, 'numpad-1').state);
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

function handleNumpadInput(value: string): void {
  if (value === 'cancel') {
    closeProfilePinModal();
  } else if (value === 'clear') {
    enteredPin = '';
    updatePinSlotsDisplay();
    const errorEl = document.getElementById('profile-pin-modal-error');
    if (errorEl) errorEl.hidden = true;
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
  isSubmitting = true;
  const numpadButtons = Array.from(document.querySelectorAll<HTMLButtonElement>('.numpad-btn'));
  for (const button of numpadButtons) {
    button.disabled = true;
  }

  const controller = context.getPlexController();
  controller.setHomeUserPin(enteredPin);
  const userId = activePinHomeUser.id;
  try {
    await controller.switchHomeUser(userId);
  } finally {
    isSubmitting = false;
  }

  const plexState = controller.getState();
  if (plexState.errorText !== null && plexState.errorText.includes('PIN')) {
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
  } else {
    closeProfilePinModal({ refocus: true });
  }
}

export function closeProfilePinModal(options?: { refocus?: boolean }): void {
  if (!context) return;

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
    if (activePinHomeUser) {
      focusState = focusRegistry.focusTarget(focusState, `plex-dyn-home-${activePinHomeUser.id}`).state;
    } else {
      focusState = focusRegistry.focusRoute(focusState, 'channelSetup').state;
    }
    context.setFocusState(focusState);
  }

  activePinHomeUser = null;
  enteredPin = '';
  context.renderApp();
}
