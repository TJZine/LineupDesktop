import { test } from 'node:test';
import assert from 'node:assert';
import { initializeProfilePinModal, openProfilePinModal, closeProfilePinModal, isProfilePinModalActive } from '../../renderer/profilePinModal.js';
import type { PlexHomeUserSummary } from '../../contracts/plex.js';
import type { FocusState, AppRouteId, FocusRegistry } from '../../renderer/navigation.js';
import { mountStaticRendererDom } from '../../renderer/staticDom.js';

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
  const avatarEl = new MockElement('profile-pin-avatar');
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
      if (selector === '[data-profile-pin-avatar]') {
        return avatarEl;
      }
      const slotMatch = selector.match(/\[data-pin-slot="(\d)"\]/);
      if (slotMatch) {
        return slots[parseInt(slotMatch[1])];
      }
      return null;
    },
    querySelectorAll: (selector: string) => {
      if (selector === '[data-numpad]') {
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
    let invalidationCount = 0;

    const mockController = {
      setHomeUserPin: (pin: string) => { homeUserPinSet = pin; },
      switchHomeUser: async (userId: string) => {
        switchHomeUserCalled = true;
        switchedUserId = userId;
      },
      getState: () => ({
        errorText: hasError ? 'Incorrect PIN' : null,
      }),
      invalidateProfileSwitch: () => {
        invalidationCount += 1;
        hasError = false;
      },
    };

    let focusState: FocusState = { activeId: null, activeRoute: 'channelSetup' };
    let renderAppCalled = false;
    let modalTargetsRegistered = false;

    const mockContext = {
      getPlexController: () => mockController,
      getFocusState: () => focusState,
      setFocusState: (state: FocusState) => { focusState = state; },
      getFocusRegistry: () => ({
        focusTarget: (state: FocusState, id: string) => (
          !id.startsWith('btn-profile-pin-') || (modalTargetsRegistered && modalEl.hidden === false)
            ? { state: { ...state, activeId: id }, changed: true }
            : { state, changed: false }
        ),
        focusRoute: (state: FocusState, route: AppRouteId) => ({ state: { ...state, activeId: 'default', activeRoute: route }, changed: true }),
      } as unknown as FocusRegistry),
      renderApp: () => {
        renderAppCalled = true;
        modalTargetsRegistered = modalEl.hidden === false;
      },
    };

    // Initialize
    initializeProfilePinModal(mockContext);

    await t.test('openProfilePinModal should show modal, set username, and focus the center 5', () => {
      renderAppCalled = false;
      modalTargetsRegistered = false;
      const user: PlexHomeUserSummary = { id: 'user-1', title: 'Test User', admin: false, protected: true };
      openProfilePinModal(user);

      assert.equal(isProfilePinModalActive(), true);
      assert.equal(modalEl.hidden, false);
      assert.equal(modalEl.getAttribute('aria-hidden'), 'false');
      assert.equal(nameEl.textContent, 'Test User');
      assert.equal(avatarEl.textContent, 'T');
      assert.equal(focusState.activeId, 'btn-profile-pin-5');
      assert.equal(slots[0].textContent, '');
      assert.equal(renderAppCalled, true);
      assert.equal(modalEl.hidden, false);
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
      assert.equal(prevented, false);
      assert.equal(stopped, false);

      // Press '1'
      prevented = false;
      stopped = false;
      keydown({
        key: '1',
        preventDefault: () => { prevented = true; },
        stopPropagation: () => { stopped = true; },
      } as KeyboardEvent);
      assert.equal(prevented, true);
      assert.equal(stopped, true);
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
      focusState = { activeId: 'btn-profile-profile-2', activeRoute: 'channelSetup' };
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
      assert.equal(focusState.activeId, 'btn-profile-pin-9');
      assert.equal(isProfilePinModalActive(), true);
    });

    await t.test('closeProfilePinModal should unmount keydown listeners', () => {
      closeProfilePinModal();
      assert.equal(isProfilePinModalActive(), false);
      assert.equal(windowListeners['keydown']?.length ?? 0, 0);
      assert.equal(invalidationCount, 1);
      assert.equal(hasError, false);
      assert.equal(focusState.activeId, 'btn-profile-profile-2');
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

test('Profile PIN modal keeps the upstream-shaped local header, 11-key grid, separate Cancel, and frozen focus ids', () => {
  const root = { innerHTML: '', querySelector: () => null };
  mountStaticRendererDom({
    querySelector: (selector: string) => selector === '[data-static-screen-root]' ? root : null,
  } as unknown as Document);
  const markup = root.innerHTML;
  const numpadMarkup = markup.match(/<div class="profile-pin-modal__numpad">([^]*?)<\/div>/u)?.[1] ?? '';
  assert.match(markup, /<div class="profile-pin-user" aria-hidden="true">\s*<div class="profile-pin-avatar profile-pin-avatar-fallback" data-profile-pin-avatar><\/div>\s*<\/div>\s*<header class="profile-pin-modal__header">/u);
  assert.equal(markup.match(/data-pin-slot="[0-3]"/gu)?.length, 4);
  assert.equal(numpadMarkup.match(/class="numpad-btn(?: [^"]+)?"/gu)?.length, 11);
  assert.doesNotMatch(numpadMarkup, /btn-profile-pin-cancel/u);
  assert.match(markup, /<\/div>\s*<p class="profile-pin-modal__error"[^>]*>[^<]*<\/p>\s*<button type="button" class="profile-pin-cancel" data-numpad="cancel" data-focus-id="btn-profile-pin-cancel">Cancel<\/button>/u);

  const frozenFocusIds = [
    'btn-profile-pin-1', 'btn-profile-pin-2', 'btn-profile-pin-3',
    'btn-profile-pin-4', 'btn-profile-pin-5', 'btn-profile-pin-6',
    'btn-profile-pin-7', 'btn-profile-pin-8', 'btn-profile-pin-9',
    'btn-profile-pin-backspace', 'btn-profile-pin-0', 'btn-profile-pin-cancel',
  ];
  assert.deepEqual(
    Array.from(markup.matchAll(/data-focus-id="(btn-profile-pin-[^"]+)"/gu), (match) => match[1]),
    frozenFocusIds,
  );
});
