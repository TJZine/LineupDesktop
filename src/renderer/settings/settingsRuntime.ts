import type {
  DesktopSettingsCapabilityProjection,
  DesktopSettingsErrorCode,
  DesktopSettingsIpcResult,
  DesktopSettingsSnapshot,
  DesktopSettingsValues,
  DesktopSettingsView,
} from '../../contracts/settings.js';
import {
  SETTINGS_SCHEMA_VERSION,
  cloneDesktopSettingsCapabilities,
  createDefaultDesktopSettingsValues,
  desktopSettingsValuesEqual,
} from '../../contracts/settings.js';
import type { LineupDesktopPreloadApi } from '../../contracts/shell.js';
import {
  isPersistedSettingsActionEnabled,
  nextDesktopSettingsValues,
  type PersistedSettingsActionId,
} from '../settingsSetup.js';

const DESKTOP_SETTINGS_ERROR_MESSAGES: Record<DesktopSettingsErrorCode, string> = {
  unauthorized: 'Desktop settings request was not authorized.',
  'validation-failed': 'Desktop settings request or response was invalid.',
  'revision-conflict': 'Desktop settings changed; refresh and try again.',
  'storage-unavailable': 'Desktop settings storage is unavailable.',
  'unsupported-version': 'Desktop settings require a newer compatible version.',
  'operation-failed': 'Desktop settings operation failed.',
};

export interface SettingsRuntimeState {
  values: DesktopSettingsValues;
  snapshot: DesktopSettingsSnapshot | null;
  capabilities: DesktopSettingsCapabilityProjection | null;
  loading: boolean;
  saving: boolean;
  errorCode: DesktopSettingsErrorCode | null;
  errorMessage: string | null;
}

export interface SettingsRuntimeOptions {
  settings: LineupDesktopPreloadApi['settings'];
  windowBridge: LineupDesktopPreloadApi['window'];
  onStateChanged(state: SettingsRuntimeState): void;
}

export interface SettingsRuntimeController {
  initialize(): Promise<void>;
  applyAction(action: PersistedSettingsActionId): Promise<void>;
  replaceValues(transform: (values: DesktopSettingsValues) => DesktopSettingsValues): Promise<void>;
  getState(): SettingsRuntimeState;
  cleanup(): void;
}

export function createSettingsRuntime(options: SettingsRuntimeOptions): SettingsRuntimeController {
  let generation = 0;
  let active = true;
  let getCounter = 0;
  let replaceCounter = 0;
  let currentGetRequestId: string | null = null;
  let currentReplaceRequestId: string | null = null;
  let lastAccepted: DesktopSettingsSnapshot | null = null;
  let capabilities: DesktopSettingsCapabilityProjection | null = null;
  let visibleValues = createDefaultDesktopSettingsValues();
  let pendingDesired: DesktopSettingsValues | null = null;
  let pendingDesiredRequiresPersistence = false;
  let mutationDrain: Promise<void> | null = null;
  let replacementInFlight = false;
  let fullscreenIntentInFlight = false;
  let nativeLaunchMode: DesktopSettingsValues['launchMode'] | null = null;
  let loading = true;
  let errorCode: DesktopSettingsErrorCode | null = null;
  let errorMessage: string | null = null;

  const publish = (): void => options.onStateChanged({
    values: { ...visibleValues },
    snapshot: lastAccepted === null ? null : cloneSnapshot(lastAccepted),
    capabilities: capabilities === null ? null : cloneDesktopSettingsCapabilities(capabilities),
    loading,
    saving: replacementInFlight || fullscreenIntentInFlight,
    errorCode,
    errorMessage,
  });

  const setError = (code: DesktopSettingsErrorCode | null): void => {
    errorCode = code;
    errorMessage = code === null ? null : DESKTOP_SETTINGS_ERROR_MESSAGES[code];
  };

  const readPendingDesired = (): DesktopSettingsValues | null => pendingDesired;

  const invokeGet = async (operationGeneration: number): Promise<DesktopSettingsIpcResult<DesktopSettingsView>> => {
    const requestId = `settings-get-${String(++getCounter)}`;
    currentGetRequestId = requestId;
    try {
      const result = await options.settings.getSnapshot({ requestId });
      if (operationGeneration !== generation || currentGetRequestId !== requestId || result.requestId !== requestId) {
        return operationFailure(requestId);
      }
      return result;
    } catch {
      return operationFailure(requestId);
    }
  };

  const invokeReplace = async (
    operationGeneration: number,
    expectedRevision: number,
    values: DesktopSettingsValues,
  ): Promise<DesktopSettingsIpcResult<DesktopSettingsView>> => {
    const requestId = `settings-replace-${String(++replaceCounter)}`;
    currentReplaceRequestId = requestId;
    try {
      const result = await options.settings.replace({ requestId, expectedRevision, values: { ...values } });
      if (operationGeneration !== generation || currentReplaceRequestId !== requestId || result.requestId !== requestId) {
        return operationFailure(requestId);
      }
      return result;
    } catch {
      return operationFailure(requestId);
    }
  };

  const applyFullscreenIntent = async (
    enabled: boolean,
    operationGeneration: number,
  ): Promise<'success' | 'failed' | 'stale'> => {
    try {
      const result = await options.windowBridge.setFullscreen(enabled);
      if (!active || operationGeneration !== generation) return 'stale';
      if (!result.ok) {
        setError('operation-failed');
        return 'failed';
      }
      const resultingLaunchMode = result.value.enabled ? 'fullscreen' : 'windowed';
      nativeLaunchMode = resultingLaunchMode;
      if (result.value.enabled !== enabled) {
        setError('operation-failed');
        return 'failed';
      }
      return 'success';
    } catch {
      if (!active || operationGeneration !== generation) return 'stale';
      setError('operation-failed');
      return 'failed';
    }
  };

  const restoreAcceptedState = async (operationGeneration: number): Promise<void> => {
    const accepted = lastAccepted?.values ?? createDefaultDesktopSettingsValues();
    visibleValues = { ...accepted };
    pendingDesired = null;
    pendingDesiredRequiresPersistence = false;
    if (nativeLaunchMode !== accepted.launchMode) {
      fullscreenIntentInFlight = true;
      if (operationGeneration === generation) publish();
      const restored = await applyFullscreenIntent(
        accepted.launchMode === 'fullscreen',
        operationGeneration,
      );
      fullscreenIntentInFlight = false;
      if (restored !== 'success' && restored !== 'stale') setError('operation-failed');
    }
  };

  const synchronizeDesiredLaunchMode = async (
    desired: DesktopSettingsValues,
    operationGeneration: number,
  ): Promise<'success' | 'failed' | 'stale'> => {
    if (nativeLaunchMode === desired.launchMode) return 'success';
    fullscreenIntentInFlight = true;
    publish();
    const result = await applyFullscreenIntent(
      desired.launchMode === 'fullscreen',
      operationGeneration,
    );
    fullscreenIntentInFlight = false;
    return result;
  };

  const runMutationDrain = async (): Promise<void> => {
    const operationGeneration = generation;
    let preserveOperationFailure = false;

    const recoverFromLaunchModeFailure = async (
      desired: DesktopSettingsValues,
      desiredRequiresPersistence: boolean,
    ): Promise<boolean> => {
      const supersedingDesired = readPendingDesired();
      if (supersedingDesired !== null && supersedingDesired.launchMode !== desired.launchMode) {
        return true;
      }
      preserveOperationFailure = true;
      const acceptedLaunchMode = lastAccepted?.values.launchMode ?? 'windowed';
      const latest = supersedingDesired ?? desired;
      const latestRequiresPersistence = supersedingDesired === null
        ? desiredRequiresPersistence
        : pendingDesiredRequiresPersistence;
      const corrected = { ...latest, launchMode: acceptedLaunchMode };
      visibleValues = corrected;
      pendingDesired = lastAccepted !== null && settingsEqual(corrected, lastAccepted.values)
        ? null
        : corrected;
      pendingDesiredRequiresPersistence = pendingDesired !== null && latestRequiresPersistence;
      if (nativeLaunchMode !== acceptedLaunchMode) {
        const restored = await synchronizeDesiredLaunchMode(corrected, operationGeneration);
        if (restored === 'stale') return false;
      }
      return pendingDesired !== null;
    };

    while (active && operationGeneration === generation && pendingDesired !== null) {
      let desired = { ...pendingDesired };
      let desiredRequiresPersistence = pendingDesiredRequiresPersistence;
      pendingDesired = null;
      pendingDesiredRequiresPersistence = false;

      if (nativeLaunchMode !== desired.launchMode) {
        const fullscreenResult = await synchronizeDesiredLaunchMode(desired, operationGeneration);
        if (fullscreenResult === 'stale') return;
        if (fullscreenResult === 'failed') {
          if (!(await recoverFromLaunchModeFailure(desired, desiredRequiresPersistence))) return;
          continue;
        }
      }

      if (pendingDesired !== null) continue;
      if (!desiredRequiresPersistence) continue;

      replacementInFlight = true;
      publish();
      let result = await invokeReplace(
        operationGeneration,
        lastAccepted?.revision ?? 0,
        desired,
      );
      replacementInFlight = false;
      if (!active || operationGeneration !== generation) return;

      if (!result.ok && result.error.code === 'revision-conflict') {
        const refreshed = await invokeGet(operationGeneration);
        if (!active || operationGeneration !== generation) return;
        if (refreshed.ok) {
          lastAccepted = cloneSnapshot(refreshed.value.snapshot);
          capabilities = cloneDesktopSettingsCapabilities(refreshed.value.capabilities);
          desired = { ...(pendingDesired ?? desired) };
          pendingDesired = null;
          pendingDesiredRequiresPersistence = false;
          if (nativeLaunchMode !== desired.launchMode) {
            const rebasedFullscreenResult = await synchronizeDesiredLaunchMode(
              desired,
              operationGeneration,
            );
            if (rebasedFullscreenResult === 'stale') return;
            if (rebasedFullscreenResult === 'failed') {
              if (!(await recoverFromLaunchModeFailure(desired, true))) return;
              continue;
            }
          }
          if (pendingDesired !== null) continue;
          replacementInFlight = true;
          publish();
          result = await invokeReplace(operationGeneration, refreshed.value.snapshot.revision, desired);
          replacementInFlight = false;
          if (!active || operationGeneration !== generation) return;
        } else {
          setError(refreshed.error.code);
          await restoreAcceptedState(operationGeneration);
          return;
        }
      }

      if (result.ok) {
        lastAccepted = cloneSnapshot(result.value.snapshot);
        capabilities = cloneDesktopSettingsCapabilities(result.value.capabilities);
        if (pendingDesired === null) visibleValues = { ...result.value.snapshot.values };
        if (!preserveOperationFailure) setError(null);
        continue;
      }

      setError(result.error.code);
      if (result.error.code === 'revision-conflict') {
        await restoreAcceptedState(operationGeneration);
        return;
      }
      if (pendingDesired === null) {
        await restoreAcceptedState(operationGeneration);
        return;
      }
    }
  };

  const drainMutations = (): Promise<void> => {
    if (!active || pendingDesired === null) return Promise.resolve();
    if (mutationDrain !== null) return mutationDrain;
    const operationGeneration = generation;
    mutationDrain = runMutationDrain().finally(() => {
      if (!active || operationGeneration !== generation) return;
      mutationDrain = null;
      replacementInFlight = false;
      fullscreenIntentInFlight = false;
      currentReplaceRequestId = null;
      publish();
      if (pendingDesired !== null) void drainMutations();
    });
    return mutationDrain;
  };

  return {
    initialize: async () => {
      const operationGeneration = generation;
      loading = true;
      publish();
      const result = await invokeGet(operationGeneration);
      if (operationGeneration !== generation) return;
      currentGetRequestId = null;
      if (!result.ok) {
        loading = false;
        setError(result.error.code);
        publish();
        return;
      }
      lastAccepted = cloneSnapshot(result.value.snapshot);
      capabilities = cloneDesktopSettingsCapabilities(result.value.capabilities);
      visibleValues = { ...result.value.snapshot.values };
      setError(null);
      pendingDesired = { ...result.value.snapshot.values };
      pendingDesiredRequiresPersistence = false;
      await drainMutations();
      if (!active || operationGeneration !== generation) return;
      loading = false;
      publish();
    },
    applyAction: async (action) => {
      if (!active || lastAccepted === null) return;
      if (!isPersistedSettingsActionEnabled(action, capabilities)) return;
      const desired = nextDesktopSettingsValues(visibleValues, action);
      visibleValues = desired;
      pendingDesired = { ...desired };
      pendingDesiredRequiresPersistence = true;
      setError(null);
      publish();
      await drainMutations();
    },
    replaceValues: async (transform) => {
      if (!active || lastAccepted === null) return;
      const desired = transform({ ...visibleValues });
      visibleValues = desired;
      pendingDesired = { ...desired };
      pendingDesiredRequiresPersistence = true;
      setError(null);
      publish();
      await drainMutations();
    },
    getState: () => ({
      values: { ...visibleValues },
      snapshot: lastAccepted === null ? null : cloneSnapshot(lastAccepted),
      capabilities: capabilities === null ? null : cloneDesktopSettingsCapabilities(capabilities),
      loading,
      saving: replacementInFlight || fullscreenIntentInFlight,
      errorCode,
      errorMessage,
    }),
    cleanup: () => {
      active = false;
      generation += 1;
      currentGetRequestId = null;
      currentReplaceRequestId = null;
      pendingDesired = null;
      pendingDesiredRequiresPersistence = false;
      replacementInFlight = false;
      fullscreenIntentInFlight = false;
      mutationDrain = null;
    },
  };
}

function operationFailure(requestId: string): DesktopSettingsIpcResult<DesktopSettingsView> {
  return {
    ok: false,
    requestId,
    error: {
      code: 'operation-failed',
      message: DESKTOP_SETTINGS_ERROR_MESSAGES['operation-failed'],
    },
  };
}

function cloneSnapshot(snapshot: DesktopSettingsSnapshot): DesktopSettingsSnapshot {
  return {
    schemaVersion: SETTINGS_SCHEMA_VERSION,
    revision: snapshot.revision,
    status: snapshot.status,
    values: { ...snapshot.values },
  };
}

function settingsEqual(left: DesktopSettingsValues, right: DesktopSettingsValues): boolean {
  return desktopSettingsValuesEqual(left, right);
}
