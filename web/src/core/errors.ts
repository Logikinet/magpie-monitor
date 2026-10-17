export type MagpieError = {
  kind:
    | 'unauthorized'
    | 'forbidden'
    | 'badStatus'
    | 'network'
    | 'timeout'
    | 'decoding'
    | 'cors'
    | 'mixedContent'
    | 'aborted';
  status?: number;
};
import { t } from '../i18n';
export function errorMessage(
  err: MagpieError,
  ctx: {
    api?: 'gateway' | 'web';
    mode?: string;
  } = {},
) {
  if (err.kind === 'unauthorized' && ctx.api === 'web') return t('errors.unauthorizedWeb');
  switch (err.kind) {
    case 'unauthorized':
      return t('errors.unauthorized');
    case 'forbidden':
      return t('errors.forbidden');
    case 'cors':
      return t('errors.cors');
    case 'mixedContent':
      return t('errors.mixedContent');
    case 'timeout':
      return t('errors.timeout');
    case 'decoding':
      return t('errors.decoding');
    case 'aborted':
      return t('errors.aborted');
    case 'badStatus':
      return t('errors.badStatus');
    default:
      return t('errors.network');
  }
}
export const zhMessage = errorMessage;
