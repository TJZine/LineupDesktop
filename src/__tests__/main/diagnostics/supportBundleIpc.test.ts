import test from 'node:test';
import assert from 'node:assert/strict';
import type { IpcMainInvokeEvent } from 'electron';

import {
  LINEUP_DIAGNOSTICS_EXPORT_SUPPORT_BUNDLE_CHANNEL,
  LINEUP_DIAGNOSTICS_GET_SUMMARY_CHANNEL,
  LINEUP_DIAGNOSTICS_RECORD_RENDERER_EVENT_CHANNEL,
} from '../../../contracts/ipc.js';
import { DiagnosticEventStore } from '../../../main/diagnostics/diagnosticEventStore.js';
import { registerDiagnosticsIpcHandlers } from '../../../main/diagnostics/supportBundleIpc.js';

test('diagnostics IPC records authorized renderer events and rejects forbidden fields', async () => {
  const ipcMain = new IpcMainDouble();
  const store = new DiagnosticEventStore({
    clock: () => 1000,
    idGenerator: () => 'renderer-event-1',
  });
  registerDiagnosticsIpcHandlers({
    eventStore: store,
    shellMode: 'development',
    isAuthorizedEvent: () => true,
    createRequestId: () => 'diagnostics-request',
    parentDirectoryProvider: () => null,
    ipcMain,
  });

  const result = await ipcMain.invoke(LINEUP_DIAGNOSTICS_RECORD_RENDERER_EVENT_CHANNEL, {}, {
    requestId: 'renderer-request-1',
    event: {
      surface: 'renderer',
      category: 'support-bundle-export',
      severity: 'info',
      operation: 'support-bundle.export.click',
      message: 'Support bundle export requested.',
      context: { route: 'settings' },
    },
  }) as { ok: boolean; value: { surface: string; category: string } };

  assert.equal(result.ok, true);
  assert.equal(result.value.surface, 'renderer');
  assert.equal(result.value.category, 'support-bundle-export');

  const rejected = await ipcMain.invoke(LINEUP_DIAGNOSTICS_RECORD_RENDERER_EVENT_CHANNEL, {}, {
    requestId: 'renderer-request-2',
    event: {
      surface: 'renderer',
      category: 'support-bundle-export',
      severity: 'info',
      operation: 'support-bundle.export.click',
      message: 'Support bundle export requested.',
      context: { [['pa', 'th'].join('')]: ['/', 'Users', 'example', 'support'].join('') },
    },
  }) as { ok: boolean; error: { code: string } };

  assert.equal(rejected.ok, false);
  assert.equal(rejected.error.code, 'DIAGNOSTICS_VALIDATION_FAILED');
  assert.equal(JSON.stringify(rejected).includes('example'), false);

  const rejectedUnsafeRequestId = await ipcMain.invoke(
    LINEUP_DIAGNOSTICS_RECORD_RENDERER_EVENT_CHANNEL,
    {},
    {
      requestId: ['/', 'Users', 'example', 'support'].join(''),
      event: {
        surface: 'renderer',
        category: 'support-bundle-export',
        severity: 'info',
        operation: 'support-bundle.export.click',
        message: 'Support bundle export requested.',
      },
    },
  ) as { ok: boolean; requestId: string; error: { code: string } };

  assert.equal(rejectedUnsafeRequestId.ok, false);
  assert.equal(rejectedUnsafeRequestId.requestId, 'diagnostics-request');
  assert.equal(rejectedUnsafeRequestId.error.code, 'DIAGNOSTICS_VALIDATION_FAILED');
  assert.equal(JSON.stringify(rejectedUnsafeRequestId).includes('example'), false);

  const rejectedUnsafeContextValue = await ipcMain.invoke(
    LINEUP_DIAGNOSTICS_RECORD_RENDERER_EVENT_CHANNEL,
    {},
    {
      requestId: 'renderer-request-3',
      event: {
        surface: 'renderer',
        category: 'support-bundle-export',
        severity: 'info',
        operation: 'support-bundle.export.click',
        message: 'Support bundle export requested.',
        context: { note: ['', 'Users', 'example', 'private.mov'].join('/') },
      },
    },
  ) as { ok: boolean; error: { code: string } };

  assert.equal(rejectedUnsafeContextValue.ok, false);
  assert.equal(rejectedUnsafeContextValue.error.code, 'DIAGNOSTICS_VALIDATION_FAILED');
  assert.equal(JSON.stringify(rejectedUnsafeContextValue).includes('example'), false);

  for (const unsafeValue of [
    ['access_', 'token=abc123'].join(''),
    ['oauth', 'Token=abc123'].join(''),
    ['raw', 'IpcFrame:channel'].join(''),
    ['process', 'Id=12345'].join(''),
    ['native_', 'handle=0xabc'].join(''),
    '\\\\server\\share\\private.mov',
    ['', 'Library', 'Application Support', 'private.mov'].join('/'),
  ]) {
    const rejectedUnsafeVariant = await ipcMain.invoke(
      LINEUP_DIAGNOSTICS_RECORD_RENDERER_EVENT_CHANNEL,
      {},
      {
        requestId: 'renderer-request-4',
        event: {
          surface: 'renderer',
          category: 'support-bundle-export',
          severity: 'info',
          operation: 'support-bundle.export.click',
          message: 'Support bundle export requested.',
          context: { note: unsafeValue },
        },
      },
    ) as { ok: boolean; error: { code: string } };

    assert.equal(rejectedUnsafeVariant.ok, false, `expected rejection for ${unsafeValue}`);
    assert.equal(rejectedUnsafeVariant.error.code, 'DIAGNOSTICS_VALIDATION_FAILED');
  }
});

test('diagnostics IPC enforces authorization before store/export access', async () => {
  const ipcMain = new IpcMainDouble();
  const store = new DiagnosticEventStore();
  registerDiagnosticsIpcHandlers({
    eventStore: store,
    shellMode: 'development',
    isAuthorizedEvent: () => false,
    createRequestId: () => 'diagnostics-request',
    parentDirectoryProvider: () => {
      throw new Error('parent provider should not run');
    },
    ipcMain,
  });

  const summary = await ipcMain.invoke(LINEUP_DIAGNOSTICS_GET_SUMMARY_CHANNEL, {}) as {
    ok: boolean;
    error: { code: string };
  };
  const exported = await ipcMain.invoke(LINEUP_DIAGNOSTICS_EXPORT_SUPPORT_BUNDLE_CHANNEL, {}) as {
    status: string;
    error: { code: string };
  };

  assert.equal(summary.ok, false);
  assert.equal(summary.error.code, 'DIAGNOSTICS_UNAUTHORIZED');
  assert.equal(exported.status, 'failed');
  assert.equal(exported.error.code, 'DIAGNOSTICS_UNAUTHORIZED');
});

test('diagnostics export IPC rejects renderer-supplied paths before exporter creation', async () => {
  const ipcMain = new IpcMainDouble();
  const store = new DiagnosticEventStore();
  registerDiagnosticsIpcHandlers({
    eventStore: store,
    shellMode: 'development',
    isAuthorizedEvent: () => true,
    createRequestId: () => 'diagnostics-request',
    parentDirectoryProvider: () => {
      throw new Error('parent provider should not run');
    },
    ipcMain,
  });

  const result = await ipcMain.invoke(LINEUP_DIAGNOSTICS_EXPORT_SUPPORT_BUNDLE_CHANNEL, {}, {
    [['pa', 'th'].join('')]: ['/', 'Users', 'example', 'support'].join(''),
  }) as { status: string; error: { code: string } };

  assert.equal(result.status, 'failed');
  assert.equal(result.error.code, 'DIAGNOSTICS_VALIDATION_FAILED');
  assert.equal(JSON.stringify(result).includes('example'), false);
  assert.equal(store.getSummary().recordCount, 1);
  assert.equal(store.getSummary().surfaceCounts['support-bundle'], 1);
});

class IpcMainDouble {
  readonly handlers = new Map<string, (event: IpcMainInvokeEvent, ...args: unknown[]) => unknown>();

  handle(channel: string, handler: (event: IpcMainInvokeEvent, ...args: unknown[]) => unknown): void {
    this.handlers.set(channel, handler);
  }

  removeHandler(channel: string): void {
    this.handlers.delete(channel);
  }

  async invoke(channel: string, event: unknown, ...args: unknown[]): Promise<unknown> {
    const handler = this.handlers.get(channel);
    assert.ok(handler, `expected handler for ${channel}`);
    return handler(event as IpcMainInvokeEvent, ...args);
  }
}
