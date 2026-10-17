const sensitive = /key|cookie|authorization|password|secret|token|credential|^k$/i;
function maskString(value: string) {
  return value
    .replace(/([?&]k=)[^&#\s]+/gi, '$1[REDACTED]')
    .replace(/((?:set-cookie|cookie)\s*:\s*)[^\r\n]+/gi, '$1[REDACTED]')
    .replace(/\b(Bearer|Basic)\s+[^\s,;"']+/gi, '$1 [REDACTED]')
    .replace(/\b(?:sk|pk|key|token)-[\w-]+/gi, '[REDACTED]')
    .replace(
      /((?:[\w-]*(?:key|cookie|authorization|password|secret|token|credential)[\w-]*)["']?\s*[:=]\s*)(?:"[^"]*"|'[^']*'|[^\s&,;]+)/gi,
      '$1[REDACTED]',
    )
    .replace(/((?:set-cookie|cookie)\s*:\s*)[^\r\n]+/gi, '$1[REDACTED]');
}
export function redact(value: unknown): unknown {
  const seen = new WeakSet<object>();
  function visit(v: unknown): unknown {
    if (typeof v === 'string') return maskString(v);
    if (!v || typeof v !== 'object') return v;
    if (seen.has(v)) return '[Circular]';
    seen.add(v);
    if (Array.isArray(v)) return v.map(visit);
    const result: Record<string, unknown> = {};
    for (const [k, item] of Object.entries(v)) result[k] = sensitive.test(k) ? '[REDACTED]' : visit(item);
    return result;
  }
  return visit(value);
}
