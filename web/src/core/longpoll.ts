import type { Route, TraceEnvelope } from './decode';
import type { MagpieError } from './errors';
import { sleep as defaultSleep } from './transport';
export type TraceState = 'running' | 'offline' | 'backoff' | 'needsAuth' | 'stopped';
export interface VisibilitySource {
  readonly hidden: boolean;
  addEventListener(type: 'visibilitychange', listener: () => void): void;
  removeEventListener(type: 'visibilitychange', listener: () => void): void;
}
export function createTraceLoop(options: {
  fetchTrace: (
    after: number,
    wait: number | undefined,
    signal: AbortSignal,
    timeoutMs: number,
  ) => Promise<TraceEnvelope>;
  onRoutes: (routes: Route[]) => void;
  onEnvelope?: (envelope: TraceEnvelope) => void;
  onState?: (state: TraceState) => void;
  sleep?: (ms: number, signal?: AbortSignal) => Promise<void>;
  random?: () => number;
  now?: () => number;
  visibility?: VisibilitySource;
}) {
  const visibility = options.visibility ?? (typeof document === 'undefined' ? undefined : document);
  let running = false,
    after = 0,
    generation = 0,
    controller: AbortController | undefined,
    wanted = false;
  const pause = options.sleep ?? defaultSleep;
  let routes: Route[] = [];
  async function run(id: number) {
    let first = true;
    const active = () => running && id === generation;
    while (active()) {
      controller = new AbortController();
      const signal = controller.signal;
      try {
        options.onState?.('running');
        const env = await options.fetchTrace(after, first ? undefined : 1, signal, 35000);
        first = false;
        if (!active()) break;
        options.onEnvelope?.(env);
        if (env.seq < after) {
          routes = [];
          options.onRoutes([]);
        }
        after = env.seq;
        if (env.routes.length) {
          const merged = new Map(routes.map((r) => [r.id ?? `seq:${r.seq}`, r]));
          for (const r of env.routes) merged.set(r.id ?? `seq:${r.seq}`, r);
          routes = [...merged.values()].sort((a, b) => a.seq - b.seq).slice(-60);
          options.onRoutes(routes);
        }
        if (!env.mine) {
          options.onState?.('offline');
          await pause(5000, signal);
        } else if (!env.routes.length) await pause(250, signal);
      } catch (error) {
        if (!active()) break;
        const err = error as MagpieError;
        if (err.kind === 'unauthorized' || err.kind === 'forbidden') {
          wanted = false;
          running = false;
          visibility?.removeEventListener('visibilitychange', visibilityChanged);
          options.onState?.('needsAuth');
          break;
        }
        if (err.kind === 'aborted') {
          running = false;
          options.onState?.('stopped');
          break;
        }
        options.onState?.('backoff');
        try {
          await pause(3000, signal);
        } catch {
          break;
        }
      }
    }
  }
  function resume() {
    if (running || visibility?.hidden) return;
    running = true;
    void run(++generation);
  }
  function suspend() {
    running = false;
    generation++;
    controller?.abort();
    options.onState?.('stopped');
  }
  const visibilityChanged = () => {
    if (visibility?.hidden) suspend();
    else if (wanted) resume();
  };
  return {
    start() {
      if (wanted) return;
      wanted = true;
      visibility?.addEventListener('visibilitychange', visibilityChanged);
      resume();
    },
    stop() {
      wanted = false;
      visibility?.removeEventListener('visibilitychange', visibilityChanged);
      suspend();
    },
    get lastSeq() {
      return after;
    },
  };
}
export function createPoller(
  intervalMs: number,
  task: (signal: AbortSignal) => void | Promise<void>,
  visibility: VisibilitySource = document,
) {
  let started = false,
    timer: ReturnType<typeof setTimeout> | undefined,
    controller: AbortController | undefined,
    generation = 0;
  const cancel = () => {
    generation++;
    clearTimeout(timer);
    controller?.abort();
  };
  async function tick() {
    if (!started || visibility.hidden) return;
    const id = generation;
    controller = new AbortController();
    try {
      await task(controller.signal);
    } catch {
      /* The task owns its error state. */
    } finally {
      if (started && !visibility.hidden && id === generation)
        timer = setTimeout(() => void tick(), intervalMs);
    }
  }
  const changed = () => {
    cancel();
    if (!visibility.hidden) void tick();
  };
  return {
    start() {
      if (started) return;
      started = true;
      visibility.addEventListener('visibilitychange', changed);
      void tick();
    },
    stop() {
      started = false;
      cancel();
      visibility.removeEventListener('visibilitychange', changed);
    },
  };
}
