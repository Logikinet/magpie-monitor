export interface Keys {
  gatewayKey?: string;
  webKey?: string;
}
export function createKeyStore(session: Storage = sessionStorage, local: Storage = localStorage) {
  const prefix = 'magpie.keys.';
  const key = (id: string) => prefix + id;
  function getKeys(id: string): Keys {
    try {
      const value = JSON.parse(session.getItem(key(id)) ?? local.getItem(key(id)) ?? '{}') as Keys;
      return {
        gatewayKey: typeof value.gatewayKey === 'string' ? value.gatewayKey : undefined,
        webKey: typeof value.webKey === 'string' ? value.webKey : undefined,
      };
    } catch {
      return {};
    }
  }
  function setKeys(id: string, keys: Keys, remember = false) {
    const value = JSON.stringify({ gatewayKey: keys.gatewayKey, webKey: keys.webKey });
    const target = remember ? local : session,
      other = remember ? session : local;
    target.setItem(key(id), value);
    other.removeItem(key(id));
  }
  function rememberKeys(id: string, remember: boolean) {
    setKeys(id, getKeys(id), remember);
  }
  function clearKeys(id?: string) {
    for (const storage of [session, local]) {
      if (id !== undefined) storage.removeItem(key(id));
      else
        for (let i = storage.length - 1; i >= 0; i--) {
          const k = storage.key(i);
          if (k?.startsWith(prefix)) storage.removeItem(k);
        }
    }
  }
  return {
    getKeys,
    setKeys,
    rememberKeys,
    clearKeys,
    isRemembered: (id: string) => local.getItem(key(id)) !== null,
  };
}
export const getKeys = (id: string) => createKeyStore().getKeys(id);
export const setKeys = (id: string, keys: Keys, remember = false) =>
  createKeyStore().setKeys(id, keys, remember);
export const rememberKeys = (id: string, remember: boolean) => createKeyStore().rememberKeys(id, remember);
export const clearKeys = (id?: string) => createKeyStore().clearKeys(id);
