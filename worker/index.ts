import { proxy, secureResponse, type Env, type Binding } from './proxy';
export interface WorkerEnv extends Env {
  ASSETS: Binding;
}
export default {
  async fetch(request: Request, env: WorkerEnv, _ctx: ExecutionContext): Promise<Response> {
    const path = new URL(request.url).pathname;
    if (path === '/proxy' || path.startsWith('/proxy/')) return proxy(request, env);
    return secureResponse(await env.ASSETS.fetch(request), true);
  },
};
