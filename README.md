# ほいくつなぐ

保育施設向けICTアプリ。出欠連絡・連絡帳・午睡チェックを1つの園アプリにまとめる構想です。
保育士用と保護者用はアプリを分け、まず保育士用から作っています。

## いまあるもの

- **午睡チェック（保育士用 v0.2）**
  - 職員ごとのログイン、管理者／職員の権限
  - 園の複数のタブレットで同じ記録を共有（15秒ごとに更新）
  - Wi-Fi が切れても記録を続けられ、つながったら自動で送信
  - 設計：[docs/gosui-check-design.md](docs/gosui-check-design.md)、[docs/server-design.md](docs/server-design.md)

## 構成

| フォルダ | 中身 |
|---|---|
| `app/` | 画面（PWA）。ビルド不要の HTML / CSS / JavaScript |
| `worker/` | サーバー（Cloudflare Workers）。ログインとAPI |
| `migrations/` | データベース（Cloudflare D1）の定義 |
| `scripts/` | 園と最初の管理者を作るスクリプト |
| `tests/` | テスト（`npm test`） |

## 手元で動かす

```sh
npm install
npm run db:migrate:local
node scripts/create-facility.mjs "テスト園" admin "テスト管理者"   # 初期パスワードが表示される
npx wrangler d1 execute hoiku-tsunagu --local --file .setup/facility.sql
npm run dev        # http://localhost:8787
npm test
```

サーバーなしで画面だけ試す場合は `npm run demo`（http://localhost:8080 の「デモで試す」）。

## 本番に公開する（Cloudflare）

Cloudflare のアカウントが必要です。料金・無料枠の範囲は Cloudflare の公式の料金ページで確認してください。

1. `npm install` のあと `npx wrangler login`（ブラウザで Cloudflare にログイン）
2. `npx wrangler d1 create hoiku-tsunagu` を実行し、表示された `database_id` を `wrangler.toml` に書き写す
3. `npm run db:migrate:remote`（データベースの表を作る）
4. 園と最初の管理者を作る
   ```sh
   node scripts/create-facility.mjs "園の名前" ログインID "管理者の名前"
   npx wrangler d1 execute hoiku-tsunagu --remote --file .setup/facility.sql
   ```
   表示された初期パスワードでログインし、設定タブから変更する。終わったら `.setup/` フォルダを削除する
5. `npm run deploy` で公開。表示された URL をタブレットで開き、「ホーム画面に追加」する

実在の園児の情報を入れる前に、[docs/server-design.md](docs/server-design.md) の「まだやっていないこと」を確認してください。
