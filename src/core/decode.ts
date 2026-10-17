/** Decoders accept wire drift, retain only known fields, and count rejected children. */
export const toNumber = (v: unknown): number | undefined => typeof v === 'number' && Number.isFinite(v) ? v : typeof v === 'string' && v.trim() !== '' && Number.isFinite(Number(v)) ? Number(v) : undefined;
export const toStr = (v: unknown): string | undefined => typeof v === 'string' ? v : typeof v === 'number' && Number.isFinite(v) ? String(v) : undefined;
export const toBool = (v: unknown): boolean | undefined => v === true || v === 1 || v === 'true' || v === '1' ? true : v === false || v === 0 || v === 'false' || v === '0' ? false : undefined;
export function parseTime(v: unknown): {
    date?: Date;
    raw?: string;
} { const raw = toStr(v); if (raw === undefined)
    return {}; const date = new Date(raw); return Number.isNaN(date.getTime()) ? { raw } : { date, raw }; }
export function record(v: unknown): Record<string, unknown> { if (!v || typeof v !== 'object' || Array.isArray(v))
    throw { kind: 'decoding' }; return v as Record<string, unknown>; }
export function lossyArray<T>(decodeItem: (v: unknown) => T) { return (v: unknown): {
    items: T[];
    bad: number;
} => { const items: T[] = []; let bad = 0; if (!Array.isArray(v))
    return { items, bad: v == null ? 0 : 1 }; for (const item of v) {
    try {
        items.push(decodeItem(item));
    }
    catch {
        bad++;
    }
} return { items, bad }; }; }
type Words<S extends string> = S extends `${infer A} ${infer B}` ? A | Words<B> : S extends '' ? never : S;
function fields<S extends string = '', N extends string = '', B extends string = ''>(v: unknown, strings: S = '' as S, numbers: N = '' as N, bools: B = '' as B) { const r = record(v); const out: Record<string, unknown> = {}; for (const [keys, decode] of [[strings, toStr], [numbers, toNumber], [bools, toBool]] as const)
    for (const key of keys.split(' ').filter(Boolean)) {
        const value = decode(r[key]);
        if (value !== undefined)
            out[key] = value;
    } return out as Partial<Record<Words<S>, string> & Record<Words<N>, number> & Record<Words<B>, boolean>>; }
function required(v: unknown, key: string) { const r = record(v); const value = toStr(r[key]); if (!value)
    throw { kind: 'decoding' }; return value; }
const totals = 'calls errors input output cost tokens cache_read cache_write retried loops reasoning unpriced';
export interface Hello {
    name?: string;
    version?: string;
}
export const decodeHello = (v: unknown): Hello => fields(v, 'name version');
export interface ModelUsage {
    provider: string;
    model?: string;
    input?: number;
    output?: number;
    cost?: number;
}
export const decodeModelUsage = (v: unknown): ModelUsage => ({ ...fields(v, 'model', 'input output cost'), provider: required(v, 'provider') });
export type SeriesPoint = ReturnType<typeof decodeSeriesPoint>;
export const decodeSeriesPoint = (v: unknown) => fields(v, 'label time', totals);
export interface UsageSummary {
    [key: string]: unknown;
    calls?: number;
    errors?: number;
    input?: number;
    output?: number;
    cost?: number;
    tokens?: number;
    cache_read?: number;
    cache_write?: number;
    models: ModelUsage[];
    series: SeriesPoint[];
    bad: number;
}
export function decodeUsageSummary(v: unknown): UsageSummary { const r = record(v); const models = lossyArray(decodeModelUsage)(r.models), series = lossyArray(decodeSeriesPoint)(r.series); return { ...fields(v, 'bucket period since', totals), models: models.items, series: series.items, bad: models.bad + series.bad }; }
export interface Row {
    [key: string]: unknown;
    provider: string;
    model?: string;
    cost?: number;
    priced?: boolean;
}
export function decodeRow(v: unknown): Row { return { ...fields(v, 'operation t agent host providerKeyId providerKeyName providerAccount callerKeyId callerKeyName session_provider session_account model req served upstream session_role source callerKeyLabel agentName icon providerName access pricing_model computerName rid session subagent effort kind via computer', 'route_id cost in out cache_read cache_write reasoning ms ttft_ms status tries', 'session_official_login priced swapped routed handed_on'), provider: required(v, 'provider') }; }
export function decodeLedger(v: unknown) { const r = record(v), rows = lossyArray(decodeRow)(r.rows), series = lossyArray(decodeSeriesPoint)(r.series), groups = lossyArray((v: unknown) => fields(v, 'id callerKeyId callerKeyName', totals))(r.callerKeys); return { ...fields(v, 'period bucket', 'offset total'), callerKeys: groups.items, rows: rows.items, series: series.items, bad: rows.bad + series.bad + groups.bad }; }
export type Ledger = ReturnType<typeof decodeLedger>;
export interface QuotaSpan {
    name: string;
    used?: number;
    remaining?: number;
    resetsAt?: string;
    unlimited?: boolean;
    display?: string;
    amount?: number;
    limit?: number;
    unit?: string;
    pool?: string;
    holds?: number;
    holdsWhy?: string;
}
export const decodeQuotaSpan = (v: unknown): QuotaSpan => ({ ...fields(v, 'resetsAt display unit pool holdsWhy', 'used remaining amount limit holds', 'unlimited'), name: required(v, 'name') });
export interface Quota {
    [key: string]: unknown;
    provider: string;
    name?: string;
    windows: QuotaSpan[];
    bad: number;
}
export function decodeQuota(v: unknown): Quota { const r = record(v), windows = lossyArray(decodeQuotaSpan)(r.windows); return { ...fields(v, 'name kind plan user balance error asOf readAt until', '', 'readDeferred'), provider: required(v, 'provider'), balanceSplit: lossyArray((v: unknown) => fields(v, 'name balance', 'amount'))(r.balanceSplit).items, windows: windows.items, bad: windows.bad + lossyArray((v: unknown) => fields(v, 'name balance', 'amount'))(r.balanceSplit).bad }; }
export const fiveHourWindow = (q: Quota) => q.windows.find(w => /^(5-hour|5h)$/i.test(w.name));
export const weeklyWindow = (q: Quota) => q.windows.find(w => /^(weekly|week)$/i.test(w.name));
export const usedPercent = (w: QuotaSpan): number => Math.min(100, Math.max(0, w.used ?? (w.remaining === undefined ? 0 : 100 - w.remaining)));
export type QuotaCard = Record<string, unknown>;
export const decodeQuotaCard = (v: unknown): QuotaCard => ({ ...record(v) });
export function decodeList<T>(v: unknown, decoder: (v: unknown) => T) { const result = lossyArray(decoder)(record(v).data); return { data: result.items, bad: result.bad }; }
export const decodeQuotas = (v: unknown) => { const result = decodeList(v, decodeQuota); return { ...result, bad: result.bad + result.data.reduce((sum, quota) => sum + quota.bad, 0) }; };
export const decodeQuotaCards = (v: unknown) => decodeList(v, decodeQuotaCard);
export interface Lane {
    id?: string;
    busy?: number;
    waiting?: number;
    limit?: number;
}
export const decodeLane = (v: unknown): Lane => fields(v, 'id name provider', 'busy waiting limit');
export function decodeConcurrency(v: unknown) { const r = record(v); const source = Array.isArray(r.data) ? r.data : Object.entries(record(r.data ?? {})).map(([id, v]) => v && typeof v === 'object' && !Array.isArray(v) ? { ...record(v), id } : v); const lanes = lossyArray(decodeLane)(source); return { ...fields(v, 'object', 'requests waiting tools'), data: lanes.items, active: lossyArray((v: unknown) => fields(v, 'session', 'route'))(r.active).items, bad: lanes.bad }; }
export type Concurrency = ReturnType<typeof decodeConcurrency>;
export interface Route {
    [key: string]: unknown;
    seq: number;
    id?: string;
    time?: string;
    order: Record<string, unknown>[];
}
export function decodeRoute(v: unknown): Route { const r = record(v); const seq = toNumber(r.seq); if (seq === undefined)
    throw { kind: 'decoding' }; return { ...fields(v, 'id time agent parentSession session kind model effort tier provider leadAccount pinned error', 'status cost', 'priced done rerouted'), seq, usage: lossyArray((v: unknown) => fields(v, 'provider model', 'in out cache_read cache_write reasoning'))(r.usage).items, group: r.group ? fields(r.group, 'id name routing affinity') : undefined, rule: r.rule ? fields(r.rule, 'name reason') : undefined, subagent: r.subagent ? fields(r.subagent, 'name model effort') : undefined, order: lossyArray((v: unknown) => fields(v, 'id provider name icon kind agent plan model routing unit', 'used amount limit pace tokens rank', 'fallback turn'))(r.order).items }; }
export function decodeTraceEnvelope(v: unknown) { const r = record(v), routes = lossyArray(decodeRoute)(r.routes); return { seq: toNumber(r.seq) ?? 0, routes: routes.items, totals: fields(r.totals ?? {}, '', 'requests rerouted errors'), mine: toBool(r.mine) ?? false, now: toStr(r.now), bad: routes.bad }; }
export type TraceEnvelope = ReturnType<typeof decodeTraceEnvelope>;
export function decodeRouteEnvelope(v: unknown) { const r = record(v); return { session: toStr(r.session), seq: toNumber(r.seq) ?? 0, route: r.route == null ? null : decodeRoute(r.route) }; }
export type RouteEnvelope = ReturnType<typeof decodeRouteEnvelope>;
export function decodeHistory(v: unknown) { const r = record(v), routes = lossyArray(decodeRoute)(r.routes); return { days: lossyArray((v: unknown) => { const s = toStr(v); if (!s)
        throw {}; return s; })(r.days).items, routes: routes.items, cut: toBool(r.cut), bad: routes.bad }; }
