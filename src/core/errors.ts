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
export function zhMessage(
  err: MagpieError,
  ctx: {
    api?: 'gateway' | 'web';
    mode?: string;
  } = {},
) {
  if (err.kind === 'unauthorized' && ctx.api === 'web')
    return 'runtime key 已失效，请重新输入；建议固定 MAGPIE_WEB_KEY。';
  switch (err.kind) {
    case 'unauthorized':
      return '认证失败，请检查 gateway key。';
    case 'forbidden':
      return '访问被拒绝，请开启 Share on local network 并检查 gateway key。';
    case 'cors':
      return '请将当前网页来源列入 magpie 设置 → Network and sharing → Web pages。';
    case 'mixedContent':
      return 'HTTPS 页面无法调用 HTTP 网关，请使用 HTTPS 网关地址。';
    case 'timeout':
      return '请求超时，请稍后重试。';
    case 'decoding':
      return '服务器数据格式无法读取。';
    case 'aborted':
      return '请求已取消。';
    case 'badStatus':
      return '服务器返回异常状态，请稍后重试。';
    default:
      return '无法连接服务器，请检查地址与网络。';
  }
}
