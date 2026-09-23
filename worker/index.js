import { createApi } from './api.js';

// 画面・APIの両方に付ける安全のためのヘッダー
const SECURITY_HEADERS = {
  'x-content-type-options': 'nosniff',
  'x-frame-options': 'DENY',
  'referrer-policy': 'no-referrer',
  'content-security-policy':
    "default-src 'self'; img-src 'self' data:; style-src 'self'; script-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'",
  'strict-transport-security': 'max-age=31536000',
};

function withHeaders(res) {
  const out = new Response(res.body, res);
  for (const [k, v] of Object.entries(SECURITY_HEADERS)) out.headers.set(k, v);
  return out;
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname.startsWith('/api/')) {
      return withHeaders(await createApi({ db: env.DB })(request));
    }
    return withHeaders(await env.ASSETS.fetch(request));
  },
};
