import type { DesktopAudioOutputRow, DesktopSettingsValues } from '../../contracts/settings.js';
import type { LineupDesktopPreloadApi } from '../../contracts/shell.js';

export interface AudioSetupState {
  status: 'loading' | 'ready' | 'saving' | 'failed';
  outputs: readonly DesktopAudioOutputRow[];
  selectedId: string;
  message: string;
}

export interface AudioSetupRuntime {
  initialize(): Promise<void>;
  select(id: string): void;
  complete(): Promise<void>;
  getState(): AudioSetupState;
  cleanup(): void;
}

export function createAudioSetupRuntime(options: {
  settings: LineupDesktopPreloadApi['settings'];
  getSettingsValues(): DesktopSettingsValues;
  replaceValues(transform: (values: DesktopSettingsValues) => DesktopSettingsValues): Promise<void>;
  onStateChanged(state: AudioSetupState): void;
  onComplete(): void;
}): AudioSetupRuntime {
  let generation = 0;
  let active = true;
  let requestSequence = 0;
  let state: AudioSetupState = {
    status: 'loading',
    outputs: systemDefaultRows(),
    selectedId: 'system-default',
    message: 'Checking available audio outputs…',
  };
  const publish = (): void => options.onStateChanged(cloneState(state));

  return {
    async initialize(): Promise<void> {
      const operationGeneration = generation;
      state = { ...state, status: 'loading', message: 'Checking available audio outputs…' };
      publish();
      const requestId = `audio-setup-${String(++requestSequence)}`;
      const result = await options.settings.getAudioOutputs({ requestId }).catch(() => null);
      if (!active || operationGeneration !== generation) return;
      if (result === null || !result.ok || result.requestId !== requestId) {
        state = {
          status: 'ready',
          outputs: systemDefaultRows(),
          selectedId: 'system-default',
          message: 'Audio outputs are unavailable. You can safely use System default.',
        };
        publish();
        return;
      }
      const persistedId = options.getSettingsValues().audioOutputDeviceId;
      const persistedOutputAvailable =
        persistedId !== null && result.value.outputs.some((row) => row.id === persistedId);
      const selectedId = persistedOutputAvailable
        ? persistedId
        : 'system-default';
      state = {
        status: 'ready',
        outputs: result.value.outputs.map((row) => ({ ...row })),
        selectedId,
        message: persistedId !== null && !persistedOutputAvailable
          ? 'The saved output is unavailable. System Default will be used.'
          : result.value.status === 'unavailable'
          ? 'Audio outputs are unavailable. You can safely use System default.'
          : result.value.status === 'partial'
            ? 'Some audio outputs were omitted for safety.'
            : 'Choose the audio output Lineup Desktop should use.',
      };
      publish();
    },
    select(id: string): void {
      if (!active || state.status === 'saving' || !state.outputs.some((row) => row.id === id)) return;
      state = { ...state, selectedId: id, status: 'ready' };
      publish();
    },
    async complete(): Promise<void> {
      if (!active || state.status !== 'ready') return;
      const operationGeneration = generation;
      const selectedId = state.selectedId;
      const selectedRow = state.outputs.find((row) => row.id === selectedId);
      const selectedDeviceId = selectedRow?.kind === 'device' ? selectedRow.id : null;
      state = { ...state, status: 'saving', message: 'Saving audio setup…' };
      publish();
      await options.replaceValues((values) => ({
        ...values,
        audioOutputDeviceId: selectedDeviceId,
        audioSetupCompleted: true,
      }));
      if (!active || operationGeneration !== generation) return;
      const values = options.getSettingsValues();
      const expectedId = selectedDeviceId;
      if (!values.audioSetupCompleted || values.audioOutputDeviceId !== expectedId) {
        state = {
          ...state,
          status: 'failed',
          message: 'Could not save audio setup. Check desktop settings storage and try again.',
        };
        publish();
        return;
      }
      state = { ...state, status: 'ready', message: 'Audio setup saved.' };
      publish();
      options.onComplete();
    },
    getState: () => cloneState(state),
    cleanup(): void {
      active = false;
      generation += 1;
    },
  };
}

function systemDefaultRows(): readonly DesktopAudioOutputRow[] {
  return [{ kind: 'system-default', id: 'system-default', label: 'System default' }];
}

function cloneState(state: AudioSetupState): AudioSetupState {
  return { ...state, outputs: state.outputs.map((row) => ({ ...row })) };
}
