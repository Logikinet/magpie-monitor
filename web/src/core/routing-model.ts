// Adapted from yetone/magpie (MIT), internal/gui/assets/plugins/routing/client.js @7660399
import type { Route, Seat, TraceEnvelope } from './decode';

type Try = NonNullable<Route['tries']>[number];
export type SeatState = 'trying' | 'answered' | 'rest' | 'idle';
export interface StatusText {
  kind: 'trying' | 'answered' | 'resting' | 'remaining' | 'credits' | 'single-key' | 'ready';
  params: Record<string, string | number | null>;
}
const number = (v: unknown): number | null =>
  typeof v === 'number' && Number.isFinite(v) && v >= 0 ? v : null;
const time = (v: unknown): number | null => {
  if (typeof v !== 'string') return null;
  const n = Date.parse(v);
  return Number.isFinite(n) ? n : null;
};
export const seatKey = (s: Pick<Seat, 'id' | 'model'>): string => `${s.id ?? ''}\0${s.model ?? ''}`;
export const matchSeat = (seats: readonly Seat[], tr: Pick<Try, 'id' | 'model'>): Seat | undefined =>
  tr.id === undefined
    ? undefined
    : (seats.find((s) => seatKey(s) === seatKey(tr)) ?? seats.find((s) => s.id === tr.id));
export const failedTry = (tr: Try): boolean =>
  !!(tr.fail || tr.error || (tr.status !== undefined && tr.status >= 400));
const handedOff = (tr: Try) => !!(tr.gone || tr.earlier || tr.again || tr.replan);
const successful = (tr: Try) =>
  tr.done && tr.status !== undefined && tr.status < 400 && !failedTry(tr) && !handedOff(tr);

export function seatState(seat: Seat, route: Route, now: number): SeatState {
  const tries = (route.tries ?? []).filter((tr) => matchSeat(route.order, tr) === seat);
  if (tries.some((tr) => !tr.done && !failedTry(tr) && !handedOff(tr))) return 'trying';
  if (tries.some(successful)) return 'answered';
  const rest = tries.filter((tr) => tr.rest).at(-1)?.rest ?? seat.rest;
  // A model-specific rest must not dim the account's other models.
  if (rest && (!rest.model || rest.model === seat.model) && (time(rest.until) ?? -Infinity) > now)
    return 'rest';
  return 'idle';
}
export function seatStatus(seat: Seat, route: Route, now: number): StatusText {
  const state = seatState(seat, route, now);
  if (state === 'trying' || state === 'answered') return { kind: state, params: {} };
  if (state === 'rest') {
    const rest =
      (route.tries ?? []).filter((tr) => matchSeat(route.order, tr) === seat && tr.rest).at(-1)?.rest ??
      seat.rest;
    return {
      kind: 'resting',
      params: {
        reason: rest?.why ?? null,
        resetInMs: time(rest?.until) === null ? null : Math.max(0, time(rest?.until)! - now),
      },
    };
  }
  if (seat.known && number(seat.used) !== null) {
    const resets = [
      ...seat.renews,
      ...(seat.usedRenews ? [seat.usedRenews] : []),
      ...(seat.dueBy === 'reset' && seat.due ? [seat.due] : []),
    ]
      .map(time)
      .filter((n): n is number => n !== null && n > now);
    return {
      kind: 'remaining',
      params: {
        percent: 100 - Math.min(100, seat.used!),
        resetInMs: resets.length ? Math.min(...resets) - now : null,
      },
    };
  }
  if (number(seat.amount) !== null)
    return {
      kind: 'credits',
      params: { amount: seat.amount!, limit: number(seat.limit), unit: seat.unit ?? null },
    };
  return { kind: seat.kind === 'key' ? 'single-key' : 'ready', params: {} };
}

export const AGENT_HUES: Readonly<Record<string, string>> = {
  claude: '#d97757',
  codex: '#6366f1',
  gemini: '#0ea5e9',
  copilot: '#a855f7',
  cursor: '#14b8a6',
  opencode: '#eab308',
  crush: '#ec4899',
  goose: '#84cc16',
  pi: '#10b981',
  omp: '#d946ef',
  omo: '#7c3aed',
  dsh: '#06b6d4',
  commandcode: '#f97316',
  mimocode: '#3b82f6',
  deveco: '#3c99cc',
};
const spare = ['#8b5cf6', '#22c55e', '#0d9488', '#0891b2', '#ca8a04', '#db2777', '#2563eb', '#65a30d'];
export function agentHue(id: string): string {
  if (Object.hasOwn(AGENT_HUES, id)) return AGENT_HUES[id];
  let hash = 0;
  for (const c of id) hash = (hash * 31 + c.charCodeAt(0)) >>> 0;
  return spare[hash % spare.length];
}
export const newestRoutes = (routes: readonly Route[]): Route[] => [...routes].sort((a, b) => b.seq - a.seq);
export const routeWindow = (routes: readonly Route[]): Route[] => newestRoutes(routes).slice(0, 60);
export function currentRoute(routes: readonly Route[], pinnedSeq?: number | null): Route | null {
  const window = routeWindow(routes);
  return window.find((r) => r.seq === pinnedSeq) ?? window[0] ?? null;
}
export function recentAgents(routes: readonly Route[]): string[] {
  return [
    ...new Set(
      newestRoutes(routes)
        .slice(0, 10)
        .flatMap((r) => (typeof r.agent === 'string' && r.agent ? [r.agent] : [])),
    ),
  ].slice(0, 3);
}
export function groupSeats(route: Route, now: number) {
  const groups = new Map<
    string,
    {
      key: string;
      provider: string | null;
      model: string | null;
      seats: Seat[];
      accounts: number;
      available: number;
    }
  >();
  for (const seat of route.order) {
    const key = `${seat.provider ?? ''}::${seat.model ?? ''}`;
    const group = groups.get(key) ?? {
      key,
      provider: seat.provider ?? null,
      model: seat.model ?? null,
      seats: [],
      accounts: 0,
      available: 0,
    };
    group.seats.push(seat);
    group.accounts = new Set(group.seats.map((s) => s.id).filter((id) => id !== undefined)).size;
    if (
      seatState(seat, route, now) !== 'rest' &&
      !seat.held &&
      !seat.barred &&
      !seat.unlisted &&
      !seat.noCredits &&
      !seat.capped
    )
      group.available++;
    groups.set(key, group);
  }
  return [...groups.values()];
}
export function requestsForAccount(routes: readonly Route[], accountId?: string | null): Route[] {
  return newestRoutes(routes).filter((r) => !accountId || (r.tries ?? []).some((tr) => tr.id === accountId));
}
export const errorJumpTarget = (routes: readonly Route[]): Route | null =>
  newestRoutes(routes).find((r) => (number(r.status) ?? 0) >= 400 || (r.tries ?? []).some(failedTry)) ?? null;

export function latencyBreakdown(route: Route) {
  const total = number(route.ms),
    ttft = number(route.ttft),
    firstText = number(route.firstText);
  const tries = route.tries ?? [];
  const start = time(route.time),
    firstStart = time(tries[0]?.start);
  const magpie = start !== null && firstStart !== null && firstStart > start ? firstStart - start : null;
  const last = tries.at(-1),
    net = last?.net;
  // No percentages or default timings: network phases only exist when measured.
  const dns = number(net?.dns),
    tcp = number(net?.connect),
    tls = number(net?.tls),
    send = number(net?.send);
  const network = [dns, tcp, tls, send].every((v) => v !== null) ? dns! + tcp! + tls! + send! : null;
  return {
    total,
    ttft,
    firstText,
    magpie,
    network,
    vendor: number(last?.ms),
    dns,
    tcp,
    tls,
    send,
    stream: total !== null && ttft !== null && total >= ttft ? total - ttft : null,
    tries: tries.map((tr) => ({ start: time(tr.start), done: tr.done ?? null, ms: number(tr.ms) })),
  };
}
/** Decode speed requires a measured output count and decode interval. */
export function outputSpeed(route: Route | null): number | null {
  if (!route || route.reasoningHidden) return null;
  const output = number(route.out),
    reasoning = number(route.reasoning);
  const start = reasoning !== null && reasoning > 0 ? number(route.firstText) : number(route.ttft);
  const total = number(route.ms);
  if (output === null || start === null || total === null || total <= start) return null;
  const visible = output - (reasoning ?? 0);
  return visible >= 0 ? (visible * 1000) / (total - start) : null;
}
export function footSummary(route: Route | null, totals?: TraceEnvelope['totals']) {
  const usage =
    route && Array.isArray(route.usage)
      ? (route.usage as { cache_read?: number; cache_write?: number; in?: number }[])
      : [];
  const cacheRead =
    usage.length && usage.every((u) => number(u.cache_read) !== null)
      ? usage.reduce((s, u) => s + u.cache_read!, 0)
      : null;
  const input =
    usage.length && usage.every((u) => number(u.in) !== null && number(u.cache_write) !== null)
      ? usage.reduce((s, u) => s + u.in! + u.cache_write!, 0)
      : null;
  return {
    provider: typeof route?.provider === 'string' ? route.provider : null,
    model:
      typeof route?.served === 'string'
        ? route.served
        : typeof route?.model === 'string'
          ? route.model
          : null,
    ms: number(route?.ms),
    tokens: number(route?.tokens),
    output: number(route?.out),
    firstText: number(route?.ttft) ?? number(route?.tries?.find((tr) => tr.served === route.served)?.ttft),
    tokensPerSecond: outputSpeed(route),
    cacheHitPercent:
      cacheRead !== null && input !== null && cacheRead + input > 0
        ? (100 * cacheRead) / (cacheRead + input)
        : null,
    counts: {
      requests: number(totals?.requests),
      retries: number(totals?.rerouted),
      errors: number(totals?.errors),
    },
  };
}
export const CONTEXT_KINDS = ['system', 'tools', 'files', 'results', 'chat'] as const;
export type ContextCell = (typeof CONTEXT_KINDS)[number] | 'free';
export function contextCells(prompt: Route['prompt']): ContextCell[] | null {
  if (!prompt?.parts.length || number(prompt.tokens) === null || number(prompt.window) === null) return null;
  const denominator = Math.max(prompt.window!, prompt.tokens!);
  if (
    denominator <= 0 ||
    prompt.parts.some(
      (p) => number(p.tokens) === null || !CONTEXT_KINDS.includes(p.kind as (typeof CONTEXT_KINDS)[number]),
    )
  )
    return null;
  const cells: ContextCell[] = [];
  let cumulative = 0;
  for (const kind of CONTEXT_KINDS) {
    cumulative += prompt.parts.filter((p) => p.kind === kind).reduce((sum, p) => sum + p.tokens!, 0);
    const end = Math.min(400, Math.round((cumulative / denominator) * 400));
    while (cells.length < end) cells.push(kind);
  }
  while (cells.length < 400) cells.push('free');
  return cells;
}
