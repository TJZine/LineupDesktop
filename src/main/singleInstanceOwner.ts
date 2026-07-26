export interface SingleInstanceApp {
  requestSingleInstanceLock(): boolean;
  on(event: 'second-instance', listener: () => void): void;
  off(event: 'second-instance', listener: () => void): void;
  quit(): void;
}

export interface SingleInstanceWindow {
  isDestroyed(): boolean;
  isMinimized(): boolean;
  restore(): void;
  show(): void;
  focus(): void;
}

export type SingleInstanceAcquireResult =
  | Readonly<{ primary: true }>
  | Readonly<{ primary: false }>;

export class SingleInstanceOwner {
  private acquired = false;
  private closed = false;

  public constructor(
    private readonly options: Readonly<{
      app: SingleInstanceApp;
      getWindow: () => SingleInstanceWindow | null;
    }>,
  ) {}

  public acquire(): SingleInstanceAcquireResult {
    if (this.acquired || this.closed) {
      throw new Error('Single-instance ownership has already been resolved.');
    }
    if (!this.options.app.requestSingleInstanceLock()) {
      this.closed = true;
      this.options.app.quit();
      return { primary: false };
    }
    this.acquired = true;
    this.options.app.on('second-instance', this.handleSecondInstance);
    return { primary: true };
  }

  public teardown(): void {
    if (!this.acquired) return;
    this.acquired = false;
    this.closed = true;
    this.options.app.off('second-instance', this.handleSecondInstance);
  }

  private readonly handleSecondInstance = (): void => {
    const window = this.options.getWindow();
    if (window === null || window.isDestroyed()) return;
    if (window.isMinimized()) window.restore();
    window.show();
    window.focus();
  };
}
