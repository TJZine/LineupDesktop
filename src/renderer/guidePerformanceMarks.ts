export type GuideInputKind = 'arrow' | 'page' | 'wheel' | 'scroll' | 'pointer' | 'gamepad' | 'other';
export type GuideRequestOrigin = 'foreground' | 'poll' | 'warm';
export type GuideRequestClass = 'renderer-cache' | 'runtime' | 'rejected';
type GuideMarkName = 'input-received' | 'input-accepted' | 'request-start' | 'request-settled' |
  'state-accepted' | 'reconcile-start' | 'reconcile-end';
type GuideMarkDetail = Readonly<Record<string, string | number | boolean>>;
type ActiveGuideRequest = Readonly<{
  sequence: number; generation: number; channelOffset: number; channelLimit: number;
  windowStartMs: number; windowDurationMs: number;
}>;

export class GuidePerformanceMarkOwner {
  private sequence = 0;
  private input: Readonly<{ sequence: number; kind: GuideInputKind; reconciled: boolean }> | null = null;
  private pendingLoading: Readonly<{ sequence: number; generation: number }> | null = null;
  private request: ActiveGuideRequest | null = null;
  private finalRequestSequence = 0;

  public constructor(private readonly performance: {
    mark(name: string, options: { detail: GuideMarkDetail }): unknown;
    clearMarks(name: string): void;
  }) {}

  public inputReceived(inputKind: GuideInputKind): void {
    this.input = { sequence: ++this.sequence, kind: inputKind, reconciled: false };
    this.emit('input-received', { sequence: this.input.sequence, inputKind, targetIndex: -1 });
  }
  public inputAccepted(inputKind: GuideInputKind, targetIndex = -1): void {
    const matched = this.input?.kind === inputKind && !this.input.reconciled ? this.input : null;
    const acceptedKind = matched === null && (inputKind === 'arrow' || inputKind === 'page') ? 'other' : inputKind;
    const sequence = matched?.sequence ?? ++this.sequence;
    this.input = { sequence, kind: acceptedKind, reconciled: false };
    this.emit('input-accepted', { sequence, inputKind: acceptedKind, targetIndex });
  }
  public requestStarted(generation: number, channelOffset: number, channelLimit: number,
    windowStartMs: number, windowDurationMs: number, requestOrigin: GuideRequestOrigin): number {
    const pendingSequence = this.pendingLoading?.generation === generation
      ? this.pendingLoading.sequence : requestOrigin === 'foreground' ? this.input?.sequence : null;
    const sequence = pendingSequence ?? ++this.sequence;
    this.request = { sequence, generation, channelOffset, channelLimit, windowStartMs, windowDurationMs };
    if (this.input?.sequence === sequence) this.input = null;
    this.pendingLoading = null;
    this.emit('request-start', { ...this.request, requestOrigin });
    return sequence;
  }
  public requestSettled(sequence: number, generation: number, requestClass: GuideRequestClass,
    accepted: boolean, requestOrigin: GuideRequestOrigin): void {
    const request = this.request?.sequence === sequence ? this.request : null;
    this.emit('request-settled', { ...request, sequence, generation, requestClass, requestOrigin,
      accepted });
    if (!accepted && request !== null) this.request = null;
  }
  public stateAccepted(generation: number, stateClass: 'loading' | 'ready', targetIndex: number): void {
    const request = this.request?.generation === generation ? this.request : null;
    const sequence = request?.sequence ?? this.input?.sequence ?? ++this.sequence;
    this.emit('state-accepted', { sequence, generation, stateClass, targetIndex });
    if (request === null && stateClass === 'loading') this.pendingLoading = { sequence, generation };
    if (request !== null && stateClass === 'ready') this.finalRequestSequence = request.sequence;
  }
  public reconcileStarted(generation: number): number {
    const sequence = this.request?.generation === generation
      ? this.request.sequence : this.input?.sequence ?? ++this.sequence;
    this.emit('reconcile-start', { sequence, generation });
    return sequence;
  }
  public reconcileEnded(sequence: number, generation: number): void {
    this.emit('reconcile-end', { sequence, generation });
    if (this.request?.sequence === sequence && this.finalRequestSequence === sequence) this.request = null;
    if (this.input?.sequence === sequence) this.input = { ...this.input, reconciled: true };
  }
  public reconcile(generation: number, render: () => void): void {
    const sequence = this.reconcileStarted(generation);
    try { render(); } finally { this.reconcileEnded(sequence, generation); }
  }
  private emit(name: GuideMarkName, detail: GuideMarkDetail): void {
    const markName = `lineup-guide-v1:${name}`;
    try { this.performance.mark(markName, { detail }); } catch { /* observability is fail-open */ }
    try { this.performance.clearMarks(markName); } catch { /* observability is fail-open */ }
  }
}

export const guidePerformanceMarks = new GuidePerformanceMarkOwner(globalThis.performance);

export function classifyGuideKeyboardInput(event: Pick<KeyboardEvent, 'key'>): GuideInputKind {
  if (event.key === 'PageUp' || event.key === 'PageDown') return 'page';
  return event.key.startsWith('Arrow') ? 'arrow' : 'other';
}
