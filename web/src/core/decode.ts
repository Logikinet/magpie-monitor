/** Decoders accept wire drift, retain only known fields, and count rejected children. */
export const toNumber = (v: unknown): number | undefined =>
  typeof v === 'number' && Number.isFinite(v)
    ? v
    : typeof v === 'string' && v.trim() !== '' && Number.isFinite(Number(v))
      ? Number(v)
      : undefined;
export const toStr = (v: unknown): string | undefined =>
  typeof v === 'string' ? v : typeof v === 'number' && Number.isFinite(v) ? String(v) : undefined;
export const toBool = (v: unknown): boolean | undefined =>
  v === true || v === 1 || v === 'true' || v === '1'
    ? true
    : v === false || v === 0 || v === 'false' || v === '0'
      ? false
      : undefined;
export function parseTime(v: unknown): {
  date?: Date;
  raw?: string;
} {
  const raw = toStr(v);
  if (raw === undefined) return {};
  const date = new Date(raw);
  return Number.isNaN(date.getTime()) ? { raw } : { date, raw };
}
export function record(v: unknown): Record<string, unknown> {
  if (!v || typeof v !== 'object' || Array.isArray(v)) throw { kind: 'decoding' };
  return v as Record<string, unknown>;
}
export function lossyArray<T>(decodeItem: (v: unknown) => T) {
  return (
    v: unknown,
  ): {
    items: T[];
    bad: number;
  } => {
    const items: T[] = [];
    let bad = 0;
    if (!Array.isArray(v)) return { items, bad: v == null ? 0 : 1 };
    for (const item of v) {
      try {
        items.push(decodeItem(item));
      } catch {
        bad++;
      }
    }
    return { items, bad };
  };
}
type Words<S extends string> = S extends `${infer A} ${infer B}` ? A | Words<B> : S extends '' ? never : S;
function fields<S extends string = '', N extends string = '', B extends string = ''>(
  v: unknown,
  strings: S = '' as S,
  numbers: N = '' as N,
  bools: B = '' as B,
) {
  const r = record(v);
  const out: Record<string, unknown> = {};
  for (const [keys, decode] of [
    [strings, toStr],
    [numbers, toNumber],
    [bools, toBool],
  ] as const)
    for (const key of keys.split(' ').filter(Boolean)) {
      const value = decode(r[key]);
      if (value !== undefined) out[key] = value;
    }
  return out as Partial<Record<Words<S>, string> & Record<Words<N>, number> & Record<Words<B>, boolean>>;
}
function required(v: unknown, key: string) {
  const r = record(v);
  const value = toStr(r[key]);
  if (!value) throw { kind: 'decoding' };
  return value;
}
const totals =
  'calls errors input output cost tokens cache_read cache_write retried loops reasoning unpriced';
export interface Hello {
  name?: string;
  version?: string;
}
export const decodeHello = (v: unknown): Hello => fields(v, 'name version');
export const decodeLimit = (v: unknown) => {
  const r = record(v);
  const result: Record<string, string | number | boolean> = {};
  for (const [key, value] of Object.entries(r)) {
    const number = toNumber(value);
    if (typeof value === 'string' || typeof value === 'boolean') result[key] = value;
    else if (number !== undefined) result[key] = number;
  }
  return result;
};
export interface ModelUsage {
  provider: string;
  model?: string;
  input?: number;
  output?: number;
  cost?: number;
}
export const decodeModelUsage = (v: unknown): ModelUsage => ({
  ...fields(v, 'model', 'input output cost'),
  provider: required(v, 'provider'),
});
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
export function decodeUsageSummary(v: unknown): UsageSummary {
  const r = record(v);
  const models = lossyArray(decodeModelUsage)(r.models),
    series = lossyArray(decodeSeriesPoint)(r.series);
  return {
    ...fields(v, 'bucket period since', totals),
    models: models.items,
    series: series.items,
    bad: models.bad + series.bad,
  };
}
export interface Row {
  [key: string]: unknown;
  provider: string;
  model?: string;
  cost?: number;
  priced?: boolean;
}
export function decodeRow(v: unknown): Row {
  return {
    ...fields(
      v,
      'operation t agent host providerKeyId providerKeyName providerAccount callerKeyId callerKeyName session_provider session_account model req served upstream session_role source callerKeyLabel agentName icon providerName access pricing_model computerName rid session subagent effort kind via computer',
      'route_id cost in out cache_read cache_write reasoning ms ttft_ms status tries',
      'session_official_login priced swapped routed handed_on',
    ),
    provider: required(v, 'provider'),
  };
}
export function decodeLedger(v: unknown) {
  const r = record(v),
    rows = lossyArray(decodeRow)(r.rows),
    series = lossyArray(decodeSeriesPoint)(r.series),
    groups = lossyArray((v: unknown) => fields(v, 'id callerKeyId callerKeyName', totals))(r.callerKeys);
  return {
    ...fields(v, 'period bucket', 'offset total'),
    callerKeys: groups.items,
    rows: rows.items,
    series: series.items,
    bad: rows.bad + series.bad + groups.bad,
  };
}
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
  holds?: number | ReturnType<typeof decodeHolds>;
  runsOut?: number;
  runsOutAt?: string;
  holdsWhy?: string;
}
export const decodeQuotaSpan = (v: unknown): QuotaSpan => ({
  ...fields(
    v,
    'resetsAt startsAt display unit pool holdsWhy runsOutAt',
    'used remaining amount limit runsOut resetSecs span pace',
    'unlimited',
  ),
  holds: toNumber(record(v).holds) ?? optional(record(v).holds, decodeHolds),
  name: required(v, 'name'),
});
export interface Quota {
  [key: string]: unknown;
  provider: string;
  name?: string;
  windows: QuotaSpan[];
  bad: number;
}
export function decodeQuota(v: unknown): Quota {
  const r = record(v),
    windows = lossyArray(decodeQuotaSpan)(r.windows);
  return {
    ...fields(
      v,
      'name icon kind plan user balance error asOf readAt until renew checkinBy',
      '',
      'readDeferred held checkins checkinOff',
    ),
    ...decodeQuotaDetails(r),
    provider: required(v, 'provider'),
    balanceSplit: lossyArray((v: unknown) => fields(v, 'name balance', 'amount'))(r.balanceSplit).items,
    windows: windows.items,
    bad: windows.bad + lossyArray((v: unknown) => fields(v, 'name balance', 'amount'))(r.balanceSplit).bad,
  };
}
export const fiveHourWindow = (q: Quota) => q.windows.find((w) => /^(5-hour|5h)$/i.test(w.name));
export const weeklyWindow = (q: Quota) => q.windows.find((w) => /^(weekly|week)$/i.test(w.name));
export const usedPercent = (w: QuotaSpan): number =>
  Math.min(100, Math.max(0, w.used ?? (w.remaining === undefined ? 0 : 100 - w.remaining)));
export type QuotaCard = Record<string, unknown>;
export const decodeQuotaCard = (v: unknown): QuotaCard => ({ ...record(v) });
export function decodeList<T>(v: unknown, decoder: (v: unknown) => T) {
  const result = lossyArray(decoder)(record(v).data);
  return { data: result.items, bad: result.bad };
}
export const decodeQuotas = (v: unknown) => {
  const result = decodeList(v, decodeQuota);
  return { ...result, bad: result.bad + result.data.reduce((sum, quota) => sum + quota.bad, 0) };
};
export const decodeQuotaCards = (v: unknown) => decodeList(v, decodeQuotaCard);
export interface Lane {
  id?: string;
  busy?: number;
  waiting?: number;
  limit?: number;
}
export const decodeLane = (v: unknown): Lane => fields(v, 'id name provider', 'busy waiting limit');
export function decodeConcurrency(v: unknown) {
  const r = record(v);
  const source = Array.isArray(r.data)
    ? r.data
    : Object.entries(record(r.data ?? {})).map(([id, v]) =>
        v && typeof v === 'object' && !Array.isArray(v) ? { ...record(v), id } : v,
      );
  const lanes = lossyArray(decodeLane)(source);
  return {
    ...fields(v, 'object', 'requests waiting tools'),
    data: lanes.items,
    active: lossyArray((v: unknown) => fields(v, 'session', 'route'))(r.active).items,
    bad: lanes.bad,
  };
}
export type Concurrency = ReturnType<typeof decodeConcurrency>;
// Wire fields checked against yetone/magpie (MIT), commit 7660399; no implementation copied.
const optional = <T>(v: unknown, decode: (v: unknown) => T): T | undefined => {
  if (v == null) return undefined;
  try {
    return decode(v);
  } catch {
    return undefined;
  }
};
const strings = (v: unknown) =>
  lossyArray((v: unknown) => {
    const s = toStr(v);
    if (s === undefined) throw {};
    return s;
  })(v).items;
export const decodeRest = (v: unknown) => fields(v, 'why until by key model', 'status failures');
export function decodeSeat(v: unknown) {
  const r = record(v);
  return {
    ...fields(
      v,
      'id provider name icon preset who kind agent plan model fixed routing unit due dueBy restarts speaks noURL capBack usedRenews sunk',
      'used amount limit pace tokens rank fit capped',
      'fallback turn fast shared known learns unlisted barred held noCredits aside',
    ),
    renews: strings(r.renews),
    via: strings(r.via),
    rest: optional(r.rest, decodeRest),
  };
}
export type Seat = ReturnType<typeof decodeSeat>;
export function decodeGroup(v: unknown) {
  const r = record(v);
  return {
    ...fields(v, 'id name routing affinity', '', 'auto sink ready decides'),
    members: strings(r.members),
    via: strings(r.via),
    subs: lossyArray((v: unknown) => fields(v, 'id name routing in', 'rules'))(r.subs).items,
  };
}
export function decodeTry(v: unknown) {
  const r = record(v);
  return {
    ...fields(
      v,
      'id model effort fixed ruleEffort start served upstream tier tierServed fail error',
      'status ms ttft firstText firstReasoning flow again replan patience queued',
      'picked fast done reasoningHidden swapped routed gone earlier',
    ),
    rest: optional(r.rest, decodeRest),
    net: optional(r.net, (v) =>
      fields(v, '', 'own before asks pool dns connect tls send wait head', 'reused'),
    ),
  };
}
export function decodePrompt(v: unknown) {
  const r = record(v);
  return {
    ...fields(v, '', 'window tokens turns', 'counted held'),
    parts: lossyArray((v: unknown) => {
      const r = record(v);
      return {
        ...fields(v, 'kind', 'tokens'),
        items: lossyArray((v: unknown) => fields(v, 'name tag', 'n tokens'))(r.items).items,
      };
    })(r.parts).items,
  };
}
export interface Route {
  [key: string]: unknown;
  seq: number;
  id?: string;
  time?: string;
  order: Seat[];
  left?: Seat[];
  tries?: ReturnType<typeof decodeTry>[];
  prompt?: ReturnType<typeof decodePrompt>;
  group?: ReturnType<typeof decodeGroup>;
}
export function decodeRoute(v: unknown): Route {
  const r = record(v),
    seq = toNumber(r.seq);
  if (seq === undefined) throw { kind: 'decoding' };
  return {
    ...fields(
      v,
      'id time agent parentSession session sessionTitle kind model effort tier provider leadAccount pinned error served upstream conv folder archive',
      'status cost unpriced ms tokens out reasoning ttft firstText firstReasoning flow sent own retried queued',
      'priced done rerouted swapped routed reasoningHidden parentMatched sealedTask',
    ),
    seq,
    usage: lossyArray((v: unknown) => fields(v, 'provider model', 'in out cache_read cache_write reasoning'))(
      r.usage,
    ).items,
    group: optional(r.group, decodeGroup),
    affinity: optional(r.affinity, (v) =>
      fields(v, 'mode last at why', 'turn lastTurn cacheRead cacheWrite', 'within kept'),
    ),
    rule: optional(r.rule, (v) => fields(v, 'name reason')),
    subagent: optional(r.subagent, (v) => fields(v, 'name model effort')),
    order: lossyArray(decodeSeat)(r.order).items,
    left: lossyArray(decodeSeat)(r.left).items,
    tries: lossyArray(decodeTry)(r.tries).items,
    prompt: optional(r.prompt, decodePrompt),
  };
}
export function decodeGroups(v: unknown) {
  const r = record(v),
    groups = lossyArray(decodeGroup)(r.groups);
  const models = lossyArray((v: unknown) =>
    fields(v, 'id provider name icon model', 'context', 'ready images'),
  )(r.models);
  const pools = lossyArray((v: unknown) => {
    const r = record(v);
    return {
      ...fields(v, 'provider name icon kind routing affinity protocol', '', 'sink'),
      who: strings(r.who),
    };
  })(r.pools);
  return {
    groups: groups.items,
    models: models.items,
    pools: pools.items,
    found: toBool(r.found),
    bad: groups.bad + models.bad + pools.bad,
  };
}
export function decodeProviders(v: unknown) {
  const providers = lossyArray((v: unknown) => {
    const r = record(v);
    return {
      ...fields(
        v,
        'id name icon kind base routing affinity fetched listError',
        'exposed maxConcurrency pluginConcurrency queueLimit queueWait maxRPM priceRate',
        'ready off unlisted noModels sponsored',
      ),
      key: optional(r.key, (v) => fields(v, 'masked', '', 'set optional')),
      keyList: lossyArray((v: unknown) => fields(v, 'id name masked protocol', 'weight', 'active on'))(
        r.keyList,
      ).items,
      models: lossyArray((v: unknown) =>
        fields(v, 'id name model', 'context output', 'exposed images ready'),
      )(r.models).items,
      agents: lossyArray((v: unknown) => fields(v, 'id name icon model group', '', 'current'))(r.agents)
        .items,
      account: optional(r.account, (v) => fields(v, 'agent agentName agentIcon builtin')),
      chosen: strings(r.chosen),
      fallback: strings(r.fallback),
    };
  })(record(v).providers);
  return { providers: providers.items, bad: providers.bad };
}
export function decodeTraceEnvelope(v: unknown) {
  const r = record(v),
    routes = lossyArray(decodeRoute)(r.routes);
  return {
    seq: toNumber(r.seq) ?? 0,
    routes: routes.items,
    totals: fields(r.totals ?? {}, '', 'requests rerouted errors'),
    mine: toBool(r.mine) ?? false,
    now: toStr(r.now),
    bad: routes.bad,
  };
}
export type TraceEnvelope = ReturnType<typeof decodeTraceEnvelope>;
export function decodeRouteEnvelope(v: unknown) {
  const r = record(v);
  return {
    session: toStr(r.session),
    seq: toNumber(r.seq) ?? 0,
    route: r.route == null ? null : decodeRoute(r.route),
  };
}
export type RouteEnvelope = ReturnType<typeof decodeRouteEnvelope>;
export function decodeHistory(v: unknown) {
  const r = record(v),
    routes = lossyArray(decodeRoute)(r.routes);
  return {
    days: lossyArray((v: unknown) => {
      const s = toStr(v);
      if (!s) throw {};
      return s;
    })(r.days).items,
    routes: routes.items,
    cut: toBool(r.cut),
    bad: routes.bad,
  };
}

function decodeHolds(v: unknown) {
  const r = record(v);
  return {
    ...fields(v, 'since', 'tokens cost used', 'priced'),
    routed: optional(r.routed, (v) => fields(v, '', 'calls tokens cacheRead cacheWrite cost')),
  };
}
function decodeQuotaDetails(r: Record<string, unknown>) {
  return {
    resets: optional(r.resets, (v) => {
      const r = record(v);
      return {
        ...fields(v, 'until', 'count fiveHour weekly', 'byWindow team'),
        each: lossyArray((v: unknown) => fields(v, 'until window', 'count'))(r.each).items,
      };
    }),
    daily: optional(r.daily, (v) => ({
      ...fields(v, 'since'),
      days: lossyArray((v: unknown) => fields(v, 'day', 'used'))(record(v).days).items,
    })),
    checkin: optional(r.checkin, (v) =>
      fields(v, 'user day at outcome msg until by vendor', 'credit streak tries', 'offline'),
    ),
    balanceTrend: optional(r.balanceTrend, (v) => ({
      ...fields(v, 'fitFrom runsOut currency', 'fitStart fitNow perDay'),
      points: lossyArray((v: unknown) => fields(v, 'at', 'amount'))(record(v).points).items,
    })),
  };
}
export function decodeUsageQuotas(v: unknown) {
  const result = lossyArray(decodeQuota)(v);
  return { data: result.items, bad: result.bad + result.items.reduce((sum, q) => sum + q.bad, 0) };
}
