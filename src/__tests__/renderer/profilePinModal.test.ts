import { test } from 'node:test';
import assert from 'node:assert';
import { initializeProfilePinModal, openProfilePinModal, closeProfilePinModal, isProfilePinModalActive } from '../../renderer/profilePinModal.js';
import type { PlexHomeUserSummary } from '../../contracts/plex.js';
import type { FocusState, AppRouteId, FocusRegistry } from '../../renderer/navigation.js';

class MockElement {
  id: string;
  hidden = true;
  textContent = '';
  attributes = new Map<string, string>();
  listeners: Record<string, ((event: unknown) => void)[]> = {};
  disabled = false;
  className = '';
  classList = {
    toggle: (_className: string, _value: boolean) => {
      // Mock classList toggle method
    }
  };

  constructor(id: string) {
    this.id = id;
  }

  setAttribute(name: string, value: string): void {
    this.attributes.set(name, value);
  }

  getAttribute(name: string): string | null {
    return this.attributes.get(name) ?? null;
  }

  hasAttribute(name: string): boolean {
    return this.attributes.has(name);
  }

  addEventListener(event: string, cb: (e: unknown) => void): void {
    if (!this.listeners[event]) this.listeners[event] = [];
    this.listeners[event].push(cb);
  }

  closest(_selector: string) {
    return this;
  }
}

test('Profile PIN Modal Suite', async (t) => {
  // Mock window & document
  const windowListeners: Record<string, ((event: KeyboardEvent) => void)[]> = {};
  const globalWindow = {
    addEventListener: (event: string, cb: (e: KeyboardEvent) => void) => {
      if (!windowListeners[event]) windowListeners[event] = [];
      windowListeners[event].push(cb);
    },
    removeEventListener: (event: string, cb: (e: KeyboardEvent) => void) => {
      const idx = (windowListeners[event] ?? []).indexOf(cb);
      if (idx !== -1) windowListeners[event].splice(idx, 1);
    }
  };

  const modalEl = new MockElement('profile-pin-modal');
  const nameEl = new MockElement('profile-pin-modal-username');
  const errorEl = new MockElement('profile-pin-modal-error');
  const slots = [
    new MockElement('slot-0'),
    new MockElement('slot-1'),
    new MockElement('slot-2'),
    new MockElement('slot-3'),
  ];
  const numpadButtons = Array.from({ length: 12 }, (_, i) => {
    const btn = new MockElement(`numpad-${i}`);
    btn.className = 'numpad-btn';
    return btn;
  });

  const elementsMap: Record<string, MockElement> = {
    'profile-pin-modal': modalEl,
    'profile-pin-modal-username': nameEl,
    'profile-pin-modal-error': errorEl,
  };

  const globalDocument = {
    getElementById: (id: string) => elementsMap[id] || null,
    querySelector: (selector: string) => {
      const slotMatch = selector.match(/\[data-pin-slot="(\d)"\]/);
      if (slotMatch) {
        return slots[parseInt(slotMatch[1])];
      }
      return null;
    },
    querySelectorAll: (selector: string) => {
      if (selector === '.numpad-btn') {
        return numpadButtons;
      }
      return [];
    }
  };

  const originalDocument = Reflect.get(globalThis, 'document');
  const originalWindow = Reflect.get(globalThis, 'window');
  Object.defineProperty(globalThis, 'document', { value: globalDocument, configurable: true });
  Object.defineProperty(globalThis, 'window', { value: globalWindow, configurable: true });

  try {
    let homeUserPinSet = '';
    let switchHomeUserCalled = false;
    let switchedUserId = '';
    let hasError = false;

    const mockController = {
      setHomeUserPin: (pin: string) => { homeUserPinSet = pin; },
      switchHomeUser: async (userId: string) => {
        switchHomeUserCalled = true;
        switchedUserId = userId;
      },
      getState: () => ({
        errorText: hasError ? 'Incorrect PIN' : null,
      }),
    };

    let focusState: FocusState = { activeId: null, activeRoute: 'channelSetup' };
    let renderAppCalled = false;
    let renderAppCalls = 0;
    let modalTargetsRegistered = false;

    const mockContext = {
      getPlexController: () => mockController,
      getFocusState: () => focusState,
      setFocusState: (state: FocusState) => { focusState = state; },
      getFocusRegistry: () => ({
        focusTarget: (state: FocusState, id: string) => (
          !id.startsWith('numpad-') || (modalTargetsRegistered && modalEl.hidden === false)
            ? { state: { ...state, activeId: id }, changed: true }
            : { state, changed: false }
        ),
        focusRoute: (state: FocusState, route: AppRouteId) => ({ state: { ...state, activeId: 'default', activeRoute: route }, changed: true }),
      } as unknown as FocusRegistry),
      renderApp: () => {
        renderAppCalled = true;
        renderAppCalls += 1;
        modalTargetsRegistered = modalEl.hidden === false;
      },
    };

    // Initialize
    initializeProfilePinModal(mockContext);

    await t.test('openProfilePinModal should show modal, set username, and focus numpad-1', () => {
      renderAppCalled = false;
      renderAppCalls = 0;
      modalTargetsRegistered = false;
      const user: PlexHomeUserSummary = { id: 'user-1', title: 'Test User', admin: false, protected: true };
      openProfilePinModal(user);

      assert.equal(isProfilePinModalActive(), true);
      assert.equal(modalEl.hidden, false);
      assert.equal(modalEl.getAttribute('aria-hidden'), 'false');
      assert.equal(nameEl.textContent, 'Test User');
      assert.equal(focusState.activeId, 'numpad-1');
      assert.equal(slots[0].textContent, '');
      assert.equal(renderAppCalled, true);
      assert.equal(renderAppCalls, 2);
    });

    await t.test('Keyboard inputs should update slots and submit on 4 digits', async () => {
      const keydown = windowListeners['keydown']?.[0];
      assert.ok(keydown);

      let prevented = false;
      let stopped = false;
      keydown({
        key: 'Enter',
        preventDefault: () => { prevented = true; },
        stopPropagation: () => { stopped = true; },
      } as KeyboardEvent);
      assert.equal(prevented, true);
      assert.equal(stopped, true);

      // Press '1'
      keydown({ key: '1', preventDefault: () => {}, stopPropagation: () => {} } as KeyboardEvent);
      assert.equal(slots[0].textContent, '●');

      // Press '2'
      keydown({ key: '2', preventDefault: () => {}, stopPropagation: () => {} } as KeyboardEvent);
      assert.equal(slots[1].textContent, '●');

      // Press 'Backspace'
      keydown({ key: 'Backspace', preventDefault: () => {}, stopPropagation: () => {} } as KeyboardEvent);
      assert.equal(slots[1].textContent, '');

      // Enter digits again to complete 4 digits: '2', '3', '4'
      keydown({ key: '2', preventDefault: () => {}, stopPropagation: () => {} } as KeyboardEvent);
      keydown({ key: '3', preventDefault: () => {}, stopPropagation: () => {} } as KeyboardEvent);

      switchHomeUserCalled = false;
      keydown({ key: '4', preventDefault: () => {}, stopPropagation: () => {} } as KeyboardEvent);

      // Submission should be asynchronous
      await new Promise((resolve) => globalThis.setTimeout(resolve, 10));

      assert.equal(homeUserPinSet, '1234');
      assert.equal(switchHomeUserCalled, true);
      assert.equal(switchedUserId, 'user-1');
      // Modal should be closed now
      assert.equal(isProfilePinModalActive(), false);
      assert.equal(modalEl.hidden, true);
    });

    await t.test('openProfilePinModal handling error path', async () => {
      hasError = true;
      const user: PlexHomeUserSummary = { id: 'user-2', title: 'Error User', admin: false, protected: true };
      openProfilePinModal(user);

      const keydown = windowListeners['keydown']?.[0];
      assert.ok(keydown);

      keydown({ key: '9', preventDefault: () => {}, stopPropagation: () => {} } as KeyboardEvent);
      keydown({ key: '9', preventDefault: () => {}, stopPropagation: () => {} } as KeyboardEvent);
      keydown({ key: '9', preventDefault: () => {}, stopPropagation: () => {} } as KeyboardEvent);
      keydown({ key: '9', preventDefault: () => {}, stopPropagation: () => {} } as KeyboardEvent);

      await new Promise((resolve) => globalThis.setTimeout(resolve, 10));

      // Error should be visible, PIN reset
      assert.equal(errorEl.hidden, false);
      assert.equal(errorEl.textContent, 'Incorrect PIN');
      assert.equal(slots[0].textContent, '');
    });

    await t.test('closeProfilePinModal should unmount keydown listeners', () => {
      closeProfilePinModal({ refocus: false });
      assert.equal(isProfilePinModalActive(), false);
      assert.equal(windowListeners['keydown']?.length ?? 0, 0);
    });

  } finally {
    if (originalDocument === undefined) {
      Reflect.deleteProperty(globalThis, 'document');
    } else {
      Object.defineProperty(globalThis, 'document', { value: originalDocument, configurable: true });
    }
    if (originalWindow === undefined) {
      Reflect.deleteProperty(globalThis, 'window');
    } else {
      Object.defineProperty(globalThis, 'window', { value: originalWindow, configurable: true });
    }
  }
});
