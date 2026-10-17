export interface Profile {
    id: string;
    name: string;
    mode: 'live' | 'direct' | 'mock';
    gatewayUrl?: string;
    webPort?: number;
    webGuiUrl?: string;
    refreshSec: number;
}
const storageKey = 'magpie.profiles';
export const defaultProfile: Profile = { id: 'demo', name: '演示（模拟数据）', mode: 'mock', refreshSec: 20 };
function url(value: unknown): string | undefined { if (value === undefined || value === '')
    return undefined; if (typeof value !== 'string')
    throw new Error('地址格式无效'); const u = new URL(value); if (!['http:', 'https:'].includes(u.protocol) || u.username || u.password || u.search || u.hash)
    throw new Error('地址格式无效'); return value; }
export function validateProfile(value: unknown): Profile { if (!value || typeof value !== 'object')
    throw new Error('Profile 格式无效'); const p = value as Record<string, unknown>; if (typeof p.id !== 'string' || !p.id.trim() || typeof p.name !== 'string' || !p.name.trim() || !['live', 'direct', 'mock'].includes(String(p.mode)) || ![10, 20, 30, 60].includes(Number(p.refreshSec)))
    throw new Error('Profile 格式无效'); if (p.webPort !== undefined && (typeof p.webPort !== 'number' || !Number.isInteger(p.webPort) || p.webPort < 1 || p.webPort > 65535))
    throw new Error('端口无效'); const gatewayUrl = url(p.gatewayUrl); if (p.mode === 'direct' && !gatewayUrl)
    throw new Error('直连模式需要网关地址'); return { id: p.id, name: p.name, mode: p.mode as Profile['mode'], refreshSec: Number(p.refreshSec), gatewayUrl, webPort: p.webPort as number | undefined, webGuiUrl: url(p.webGuiUrl) }; }
export function importProfiles(json: string): Profile[] { const data: unknown = JSON.parse(json); if (!Array.isArray(data))
    throw new Error('Profile 列表格式无效'); const profiles = data.map(validateProfile); if (new Set(profiles.map(p => p.id)).size !== profiles.length)
    throw new Error('Profile ID 重复'); return profiles; }
export function exportProfiles(profiles: Profile[] = loadProfiles()): string { return JSON.stringify(profiles.map(validateProfile), null, 2); }
export function saveProfiles(profiles: Profile[], storage: Storage = localStorage) { storage.setItem(storageKey, exportProfiles(profiles)); }
export function loadProfiles(storage: Storage = localStorage): Profile[] { try {
    const data = storage.getItem(storageKey);
    if (data)
        return importProfiles(data);
}
catch { /* Recover from invalid local data. */ } return [{ ...defaultProfile }]; }
