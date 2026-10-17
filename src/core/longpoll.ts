import type { Route, TraceEnvelope } from './decode';
import type { MagpieError } from './errors';
import { sleep as defaultSleep } from './transport';
export type TraceState = 'running' | 'backoff' | 'needsAuth' | 'stopped';
export interface VisibilitySource {
    readonly hidden: boolean;
    addEventListener(type: 'visibilitychange', listener: () => void): void;
    removeEventListener(type: 'visibilitychange', listener: () => void): void;
}
export function createTraceLoop(options: {
    fetchTrace: (after: number, wait: number, signal: AbortSignal, timeoutMs: number) => Promise<TraceEnvelope>;
    onRoutes: (routes: Route[]) => void;
    onState?: (state: TraceState) => void;
    sleep?: (ms: number, signal?: AbortSignal) => Promise<void>;
    random?: () => number;
    now?: () => number;
    visibility?: VisibilitySource;
}) {
    const visibility = options.visibility ?? (typeof document === 'undefined' ? undefined : document);
    let running = false, after = 0, generation = 0, controller: AbortController | undefined, wanted = false;
    const pause = options.sleep ?? defaultSleep;
    async function run(id: number) { let failures = 0; const active = () => running && id === generation; while (active()) {
        controller = new AbortController();
        const signal = controller.signal;
        try {
            options.onState?.('running');
            const env = await options.fetchTrace(after, 1, signal, 35000);
            if (!active())
                break;
            after = Math.max(after, env.seq);
            failures = 0;
            if (env.routes.length)
                options.onRoutes(env.routes);
            else
                await pause(250, signal);
        }
        catch (error) {
            if (!active())
                break;
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
            const delay = err.kind === 'timeout' ? 250 : (options.random ?? Math.random)() * Math.min(30000, 500 * 2 ** Math.min(failures++, 16));
            options.onState?.('backoff');
            try {
                await pause(delay, signal);
            }
            catch {
                break;
            }
        }
    } }
    function resume() { if (running || visibility?.hidden)
        return; running = true; void run(++generation); }
    function suspend() { running = false; generation++; controller?.abort(); options.onState?.('stopped'); }
    const visibilityChanged = () => { if (visibility?.hidden)
        suspend();
    else if (wanted)
        resume(); };
    return { start() { if (wanted)
            return; wanted = true; visibility?.addEventListener('visibilitychange', visibilityChanged); resume(); }, stop() { wanted = false; visibility?.removeEventListener('visibilitychange', visibilityChanged); suspend(); }, get lastSeq() { return after; } };
}
export function createPoller(intervalMs: number, task: (signal: AbortSignal) => void | Promise<void>, visibility: VisibilitySource = document) {
    let started = false, timer: ReturnType<typeof setTimeout> | undefined, controller: AbortController | undefined, generation = 0;
    const cancel = () => { generation++; clearTimeout(timer); controller?.abort(); };
    async function tick() { if (!started || visibility.hidden)
        return; const id = generation; controller = new AbortController(); try {
        await task(controller.signal);
    }
    catch { /* The task owns its error state. */ }
    finally {
        if (started && !visibility.hidden && id === generation)
            timer = setTimeout(() => void tick(), intervalMs);
    } }
    const changed = () => { cancel(); if (!visibility.hidden)
        void tick(); };
    return { start() { if (started)
            return; started = true; visibility.addEventListener('visibilitychange', changed); void tick(); }, stop() { started = false; cancel(); visibility.removeEventListener('visibilitychange', changed); } };
}
