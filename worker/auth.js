// パスワードの変換・照合と、セッションの合言葉づくり（Workers と Node の両方で動く）

// Workers の PBKDF2 は 10万回が上限
const ITERATIONS = 100000;
const enc = new TextEncoder();

function toB64(bytes) {
  let s = '';
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s);
}

function fromB64(str) {
  return Uint8Array.from(atob(str), (c) => c.charCodeAt(0));
}

function toB64url(bytes) {
  return toB64(bytes).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

async function pbkdf2(password, salt, iterations) {
  const key = await crypto.subtle.importKey('raw', enc.encode(password), 'PBKDF2', false, ['deriveBits']);
  const bits = await crypto.subtle.deriveBits({ name: 'PBKDF2', hash: 'SHA-256', salt, iterations }, key, 256);
  return new Uint8Array(bits);
}

function sameBytes(a, b) {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return diff === 0;
}

export async function hashPassword(password) {
  const salt = crypto.getRandomValues(new Uint8Array(16));
  const hash = await pbkdf2(password, salt, ITERATIONS);
  return `pbkdf2$${ITERATIONS}$${toB64(salt)}$${toB64(hash)}`;
}

export async function verifyPassword(password, stored) {
  const [scheme, iter, salt, hash] = String(stored).split('$');
  if (scheme !== 'pbkdf2') return false;
  const actual = await pbkdf2(password, fromB64(salt), Number(iter));
  return sameBytes(actual, fromB64(hash));
}

// 該当する職員がいない時も同じだけ時間をかけ、IDの有無を推測されにくくする
const DUMMY_HASH = `pbkdf2$${ITERATIONS}$AAAAAAAAAAAAAAAAAAAAAA==$AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=`;
export async function burnPasswordTime(password) {
  await verifyPassword(password, DUMMY_HASH);
}

export function newToken() {
  return toB64url(crypto.getRandomValues(new Uint8Array(32)));
}

export async function sha256Hex(text) {
  const d = new Uint8Array(await crypto.subtle.digest('SHA-256', enc.encode(text)));
  return Array.from(d, (b) => b.toString(16).padStart(2, '0')).join('');
}

export const PASSWORD_MIN = 8;
