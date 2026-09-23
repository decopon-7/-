// テスト用：Cloudflare D1 と同じ呼び方で Node の SQLite を使う
import { readFileSync, readdirSync } from 'node:fs';
import { DatabaseSync } from 'node:sqlite';

export function createTestDb() {
  const sqlite = new DatabaseSync(':memory:');
  const dir = new URL('../migrations/', import.meta.url);
  for (const f of readdirSync(dir).filter((n) => n.endsWith('.sql')).sort()) {
    sqlite.exec(readFileSync(new URL(f, dir), 'utf8'));
  }
  const norm = (args) => args.map((a) => (a === undefined ? null : typeof a === 'boolean' ? Number(a) : a));
  const db = {
    sqlite,
    prepare(sql) {
      let params = [];
      const stmt = {
        bind(...args) { params = norm(args); return stmt; },
        async first() { return sqlite.prepare(sql).get(...params) ?? null; },
        async all() { return { results: sqlite.prepare(sql).all(...params) }; },
        async run() { const r = sqlite.prepare(sql).run(...params); return { meta: { changes: r.changes } }; },
      };
      return stmt;
    },
  };
  return db;
}
