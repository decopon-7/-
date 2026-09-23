// 園と最初の管理者を作るためのSQLを書き出す
// 使い方: node scripts/create-facility.mjs "園の名前" ログインID "管理者の名前"
// 初期パスワードはランダムに作って画面に表示する（ログイン後に変更してもらう）
import { mkdirSync, writeFileSync } from 'node:fs';
import { hashPassword, newToken } from '../worker/auth.js';

const [facilityName, loginId, adminName] = process.argv.slice(2);
if (!facilityName || !loginId || !adminName || !/^[a-z0-9._-]{3,32}$/.test(loginId)) {
  console.error('使い方: node scripts/create-facility.mjs "園の名前" ログインID(半角英数字3〜32字) "管理者の名前"');
  process.exit(1);
}

const q = (s) => `'${String(s).replace(/'/g, "''")}'`;
const now = Date.now();
const facilityId = crypto.randomUUID();
const userId = crypto.randomUUID();
const password = newToken().slice(0, 12);
const hash = await hashPassword(password);

const classes = [['0歳児', 0, 5, 0], ['1歳児', 1, 10, 1], ['2歳児', 2, 10, 2]];
const sql = [
  `INSERT INTO facilities (id, name, created_at) VALUES (${q(facilityId)}, ${q(facilityName)}, ${now});`,
  `INSERT INTO users (id, facility_id, login_id, name, role, password_hash, created_at) VALUES (${q(userId)}, ${q(facilityId)}, ${q(loginId)}, ${q(adminName)}, 'admin', ${q(hash)}, ${now});`,
  ...classes.map(([name, age, interval, sort]) =>
    `INSERT INTO classes (id, facility_id, name, age, interval_min, sort) VALUES (${q(crypto.randomUUID())}, ${q(facilityId)}, ${q(name)}, ${age}, ${interval}, ${sort});`),
].join('\n');

mkdirSync('.setup', { recursive: true });
writeFileSync('.setup/facility.sql', sql + '\n');
console.log('書き出しました: .setup/facility.sql');
console.log('');
console.log('次のコマンドで登録してください（本番は --remote、手元の確認は --local）:');
console.log('  npx wrangler d1 execute hoiku-tsunagu --remote --file .setup/facility.sql');
console.log('');
console.log(`ログインID: ${loginId}`);
console.log(`初期パスワード: ${password}`);
console.log('ログイン後、設定タブからパスワードを変更してください。登録が終わったら .setup/ フォルダは削除してください。');
