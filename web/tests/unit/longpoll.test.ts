import { afterEach, beforeEach, it, expect, vi } from 'vitest';
import { createPoller, createTraceLoop, type VisibilitySource } from '../../src/core/longpoll';
import { decodeTraceEnvelope } from '../../src/core/decode';
const envelope = (seq: number, routes: unknown[] = []) => decodeTraceEnvelope({ seq, routes });
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
it('backs off exponentially with full jitter, caps at 30s and resets on success', async () => {
  const delays: number[] = [];
  let sleepCalls = 0;
  const fetchTrace = vi.fn().mockImplementation(async () => {
    throw { kind: 'network' };
  });
  const loop = createTraceLoop({
    fetchTrace,
    onRoutes: vi.fn(),
    random: () => 0.5,
    sleep: (ms, signal) => {
      delays.push(ms);
      sleepCalls++;
      if (sleepCalls === 9) fetchTrace.mockResolvedValueOnce(envelope(1, [{ seq: 1 }]));
      if (sleepCalls === 10) return new Promise<void>(() => {});
      return new Promise<void>((resolve, reject) => {
        const t = setTimeout(resolve, ms);
        signal?.addEventListener('abort', () => {
          clearTimeout(t);
          reject({ kind: 'aborted' });
        });
      });
    },
  });
  loop.start();
  for (let i = 0; i < 9; i++) {
    await flush();
    await vi.advanceTimersByTimeAsync(delays[i]);
  }
  await flush();
  expect(delays.slice(0, 9)).toEqual([250, 500, 1000, 2000, 4000, 8000, 15000, 15000, 15000]);
  expect(delays[9]).toBe(250);
  loop.stop();
});
it('timeouts use short delay, unauthorized and forbidden stop until restarted', async () => {
  for (const kind of ['unauthorized', 'forbidden']) {
    const onState = vi.fn();
    const fetchTrace = vi.fn().mockRejectedValueOnce({ kind: 'timeout' }).mockRejectedValueOnce({ kind });
    const loop = createTraceLoop({ fetchTrace, onRoutes: vi.fn(), onState });
    loop.start();
    await flush();
    await vi.advanceTimersByTimeAsync(250);
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
