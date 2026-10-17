import { afterEach, beforeEach, it, expect, vi } from 'vitest';
import { createPoller, createTraceLoop, type VisibilitySource } from '../../src/core/longpoll';
import { decodeTraceEnvelope } from '../../src/core/decode';
const envelope = (seq: number, routes: unknown[] = []) => decodeTraceEnvelope({ seq, routes, mine: true });
const pending = () => new Promise<ReturnType<typeof envelope>>(() => {});
const flush = async () => {
  await vi.advanceTimersByTimeAsync(0);
};
function visibility() {
  class Visibility implements VisibilitySource {
    hidden: boolean = false;
    listeners = new Set<() => void>();
    addEventListener(_type: string, fn: () => void) {
      this.listeners.add(fn);
    }
    removeEventListener(_type: string, fn: () => void) {
      this.listeners.delete(fn);
    }
    set(hidden: boolean) {
      this.hidden = hidden;
      for (const fn of this.listeners) fn();
    }
  }
  return new Visibility();
}
beforeEach(() => vi.useFakeTimers());
afterEach(() => vi.useRealTimers());
it('advances sequence, sets 35s timeout and delays empty responses', async () => {
  const fetchTrace = vi
    .fn()
    .mockResolvedValueOnce(envelope(4, [{ seq: 4 }]))
    .mockResolvedValueOnce(envelope(5))
    .mockImplementation(pending);
  const onRoutes = vi.fn();
  const loop = createTraceLoop({ fetchTrace, onRoutes });
  loop.start();
  loop.start();
  await flush();
  expect(fetchTrace.mock.calls.map((c) => c[0])).toEqual([0, 4]);
  expect(fetchTrace.mock.calls[0][3]).toBe(35000);
  expect(onRoutes).toHaveBeenCalledTimes(1);
  await vi.advanceTimersByTimeAsync(249);
  expect(fetchTrace).toHaveBeenCalledTimes(2);
  await vi.advanceTimersByTimeAsync(1);
  expect(fetchTrace.mock.calls[2][0]).toBe(5);
  loop.stop();
});
it('retries errors after 3 seconds', async () => {
  const fetchTrace = vi.fn().mockRejectedValueOnce({ kind: 'network' }).mockImplementation(pending);
  const loop = createTraceLoop({ fetchTrace, onRoutes: vi.fn() });
  loop.start();
  await flush();
  await vi.advanceTimersByTimeAsync(2999);
  expect(fetchTrace).toHaveBeenCalledTimes(1);
  await vi.advanceTimersByTimeAsync(1);
  expect(fetchTrace).toHaveBeenCalledTimes(2);
  loop.stop();
});
it('timeouts retry after 3 seconds, unauthorized and forbidden stop until restarted', async () => {
  for (const kind of ['unauthorized', 'forbidden']) {
    const onState = vi.fn();
    const fetchTrace = vi.fn().mockRejectedValueOnce({ kind: 'timeout' }).mockRejectedValueOnce({ kind });
    const loop = createTraceLoop({ fetchTrace, onRoutes: vi.fn(), onState });
    loop.start();
    await flush();
    await vi.advanceTimersByTimeAsync(3000);
    expect(onState).toHaveBeenLastCalledWith('needsAuth');
    await vi.advanceTimersByTimeAsync(60000);
    expect(fetchTrace).toHaveBeenCalledTimes(2);
    loop.stop();
  }
});
it('stop aborts pending request and ignores late results; restart has one loop', async () => {
  let resolve: ((v: ReturnType<typeof envelope>) => void) | undefined;
  const fetchTrace = vi
    .fn()
    .mockImplementationOnce(
      () =>
        new Promise((r) => {
          resolve = r;
        }),
    )
    .mockImplementation(pending);
  const onRoutes = vi.fn();
  const loop = createTraceLoop({ fetchTrace, onRoutes });
  loop.start();
  const signal = fetchTrace.mock.calls[0][2] as AbortSignal;
  loop.stop();
  expect(signal.aborted).toBe(true);
  loop.start();
  resolve?.(envelope(99, [{ seq: 99 }]));
  await flush();
  expect(onRoutes).not.toHaveBeenCalled();
  expect(loop.lastSeq).toBe(0);
  expect(fetchTrace).toHaveBeenCalledTimes(2);
  loop.stop();
});
it('trace pauses when hidden and resumes with preserved sequence', async () => {
  const source = visibility();
  const fetchTrace = vi.fn().mockResolvedValueOnce(envelope(3)).mockImplementation(pending);
  const loop = createTraceLoop({ fetchTrace, onRoutes: vi.fn(), visibility: source });
  loop.start();
  await flush();
  source.set(true);
  await vi.advanceTimersByTimeAsync(60000);
  expect(fetchTrace).toHaveBeenCalledTimes(1);
  source.set(false);
  expect(fetchTrace.mock.calls[1][0]).toBe(3);
  loop.stop();
  source.set(false);
  expect(fetchTrace).toHaveBeenCalledTimes(2);
});
it('poller starts immediately, avoids overlap, aborts on hide, resumes immediately', async () => {
  const source = visibility();
  const task = vi.fn(async (_signal: AbortSignal) => {});
  const poller = createPoller(20000, task, source);
  poller.start();
  poller.start();
  await flush();
  expect(task).toHaveBeenCalledTimes(1);
  await vi.advanceTimersByTimeAsync(20000);
  expect(task).toHaveBeenCalledTimes(2);
  source.set(true);
  expect(task.mock.calls[1][0].aborted).toBe(true);
  await vi.advanceTimersByTimeAsync(60000);
  expect(task).toHaveBeenCalledTimes(2);
  source.set(false);
  await flush();
  expect(task).toHaveBeenCalledTimes(3);
  poller.stop();
  await vi.advanceTimersByTimeAsync(60000);
  expect(task).toHaveBeenCalledTimes(3);
});
it('poller does not start hidden and never overlaps slow tasks', async () => {
  const source = visibility();
  source.hidden = true;
  let finish: (() => void) | undefined;
  const task = vi.fn(
    () =>
      new Promise<void>((r) => {
        finish = r;
      }),
  );
  const poller = createPoller(10, task, source);
  poller.start();
  expect(task).not.toHaveBeenCalled();
  source.set(false);
  await vi.advanceTimersByTimeAsync(100);
  expect(task).toHaveBeenCalledTimes(1);
  finish?.();
  await flush();
  await vi.advanceTimersByTimeAsync(10);
  expect(task).toHaveBeenCalledTimes(2);
  poller.stop();
});

it('omits wait initially, retains 60 routes, replaces updates and clears on regression', async () => {
  const fetchTrace = vi
    .fn()
    .mockResolvedValueOnce(
      envelope(
        70,
        Array.from({ length: 70 }, (_, i) => ({ id: i + 1, seq: i + 1 })),
      ),
    )
    .mockResolvedValueOnce(envelope(71, [{ id: 70, seq: 71, done: true }]))
    .mockResolvedValueOnce(envelope(2, [{ id: 1, seq: 2 }]))
    .mockImplementation(pending);
  const onRoutes = vi.fn();
  const loop = createTraceLoop({ fetchTrace, onRoutes });
  loop.start();
  await flush();
  expect(fetchTrace.mock.calls.map((c) => c[1])).toEqual([undefined, 1, 1, 1]);
  expect(onRoutes.mock.calls[0][0]).toHaveLength(60);
  expect(onRoutes.mock.calls[1][0]).toHaveLength(60);
  expect(onRoutes.mock.calls[1][0].at(-1)).toMatchObject({ id: '70', seq: 71, done: true });
  expect(onRoutes.mock.calls[2][0]).toEqual([]);
  expect(onRoutes.mock.calls[3][0]).toMatchObject([{ id: '1', seq: 2 }]);
  expect(loop.lastSeq).toBe(2);
  loop.stop();
});
it('reports offline and retries mine=false after 5 seconds', async () => {
  const fetchTrace = vi
    .fn()
    .mockResolvedValueOnce(decodeTraceEnvelope({ mine: false, seq: 0 }))
    .mockImplementation(pending);
  const onState = vi.fn();
  const loop = createTraceLoop({ fetchTrace, onState, onRoutes: vi.fn() });
  loop.start();
  await flush();
  expect(onState).toHaveBeenLastCalledWith('offline');
  await vi.advanceTimersByTimeAsync(4999);
  expect(fetchTrace).toHaveBeenCalledTimes(1);
  await vi.advanceTimersByTimeAsync(1);
  expect(fetchTrace).toHaveBeenCalledTimes(2);
  loop.stop();
});
