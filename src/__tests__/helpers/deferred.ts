export interface Deferred<TValue> {
  promise: Promise<TValue>;
  resolve(value: TValue): void;
}

export function deferred<TValue>(): Deferred<TValue> {
  let resolveValue: (value: TValue) => void = () => undefined;
  const promise = new Promise<TValue>((resolve) => {
    resolveValue = resolve;
  });
  return {
    promise,
    resolve: resolveValue,
  };
}
