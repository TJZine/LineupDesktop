export interface ApplicationStartupCleanupSteps {
  settingsIpc: (() => void) | null;
  diagnosticsIpc: (() => void) | null;
  playerRecoveryIpc: (() => void) | null;
  playbackTransitionOwner: Readonly<{ dispose(): void }> | null;
  playerIpc: Readonly<{ teardown(): Promise<void> }> | null;
  playbackEventRouter: Readonly<{ dispose(): void }> | null;
  playbackRuntime: Readonly<{ teardown(): Promise<unknown> }> | null;
  channelComposition: (() => Promise<void>) | null;
  plexComposition: (() => Promise<void>) | null;
  singleInstanceOwner: Readonly<{ teardown(): void }> | null;
}

export type ApplicationStartupCleanupReporter = (
  message: string,
  error: unknown,
) => void;

type CleanupStep = readonly [
  name: string,
  cleanup: (() => void | Promise<unknown>) | null,
];

export async function cleanupFailedApplicationStartup(
  cleanup: ApplicationStartupCleanupSteps,
  reportDiagnostic: ApplicationStartupCleanupReporter,
): Promise<void> {
  const steps: readonly CleanupStep[] = [
    ['Settings IPC cleanup failed during startup rollback', cleanup.settingsIpc],
    ['Diagnostics IPC cleanup failed during startup rollback', cleanup.diagnosticsIpc],
    ['Player recovery IPC cleanup failed during startup rollback', cleanup.playerRecoveryIpc],
    [
      'Playback transition owner cleanup failed during startup rollback',
      disposeOwner(cleanup.playbackTransitionOwner),
    ],
    [
      'Player IPC cleanup failed during startup rollback',
      teardownOwner(cleanup.playerIpc),
    ],
    [
      'Playback event router cleanup failed during startup rollback',
      disposeOwner(cleanup.playbackEventRouter),
    ],
    [
      'Playback runtime cleanup failed during startup rollback',
      teardownOwner(cleanup.playbackRuntime),
    ],
    [
      'Channel composition cleanup failed during startup rollback',
      cleanup.channelComposition,
    ],
    ['Plex composition cleanup failed during startup rollback', cleanup.plexComposition],
    [
      'Single-instance owner cleanup failed during startup rollback',
      teardownOwner(cleanup.singleInstanceOwner),
    ],
  ];

  for (const [name, step] of steps) {
    if (step === null) {
      continue;
    }
    try {
      await step();
    } catch (error: unknown) {
      try {
        reportDiagnostic(name, error);
      } catch {
        // Startup rollback must continue even if the diagnostic sink is unavailable.
      }
    }
  }
}

function disposeOwner(
  owner: Readonly<{ dispose(): void }> | null,
): (() => void) | null {
  return owner === null ? null : () => owner.dispose();
}

function teardownOwner(
  owner: Readonly<{ teardown(): void | Promise<unknown> }> | null,
): (() => void | Promise<unknown>) | null {
  return owner === null ? null : () => owner.teardown();
}
