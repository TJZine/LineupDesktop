export interface ApplicationBeforeQuitEvent {
  preventDefault(): void;
}

export interface ApplicationQuitLifecycleOwnerOptions {
  cleanupCurrentOwners(): Promise<void>;
  waitForStartupSettlement(): Promise<void>;
  quit(): void;
  reportDiagnostic(message: string, error: unknown): void;
  startupSettlementTimeoutMs?: number;
}

const DEFAULT_STARTUP_SETTLEMENT_TIMEOUT_MS = 5_000;

export class ApplicationQuitLifecycleOwner {
  readonly #options: ApplicationQuitLifecycleOwnerOptions;
  readonly #startupSettlementTimeoutMs: number;
  #quitRequested = false;
  #quitReady = false;
  #cleanupPromise: Promise<void> | null = null;

  constructor(options: ApplicationQuitLifecycleOwnerOptions) {
    this.#options = options;
    const startupSettlementTimeoutMs = options.startupSettlementTimeoutMs;
    this.#startupSettlementTimeoutMs =
      typeof startupSettlementTimeoutMs === 'number' &&
      Number.isSafeInteger(startupSettlementTimeoutMs) &&
      startupSettlementTimeoutMs > 0
        ? startupSettlementTimeoutMs
        : DEFAULT_STARTUP_SETTLEMENT_TIMEOUT_MS;
  }

  isQuitRequested(): boolean {
    return this.#quitRequested;
  }

  handleBeforeQuit(event: ApplicationBeforeQuitEvent): void {
    this.#quitRequested = true;
    if (this.#quitReady) return;

    event.preventDefault();
    if (this.#cleanupPromise !== null) return;

    this.#cleanupPromise = this.#runCleanup().finally(() => {
      this.#quitReady = true;
      try {
        this.#options.quit();
      } catch (error: unknown) {
        this.#report('Application quit retry failed', error);
      }
    });
  }

  async #runCleanup(): Promise<void> {
    await this.#runPhase(
      'Application cleanup failed during quit',
      this.#options.cleanupCurrentOwners,
    );
    await this.#runPhase(
      'Application startup did not settle during quit',
      () => this.#waitForStartupSettlement(),
    );
    await this.#runPhase(
      'Late application cleanup failed during quit',
      this.#options.cleanupCurrentOwners,
    );
  }

  async #waitForStartupSettlement(): Promise<void> {
    let timeoutHandle: ReturnType<typeof globalThis.setTimeout> | null = null;
    const timeout = new Promise<never>((_resolve, reject) => {
      timeoutHandle = globalThis.setTimeout(() => {
        reject(new Error('Application startup settlement timed out.'));
      }, this.#startupSettlementTimeoutMs);
    });
    try {
      await Promise.race([this.#options.waitForStartupSettlement(), timeout]);
    } finally {
      if (timeoutHandle !== null) globalThis.clearTimeout(timeoutHandle);
    }
  }

  async #runPhase(message: string, phase: () => Promise<void>): Promise<void> {
    try {
      await phase();
    } catch (error: unknown) {
      this.#report(message, error);
    }
  }

  #report(message: string, error: unknown): void {
    try {
      this.#options.reportDiagnostic(message, error);
    } catch {
      // Quit must continue even when diagnostics are unavailable.
    }
  }
}
