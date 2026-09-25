# ほいくつなぐ

保育施設向けICTアプリ。出欠連絡・連絡帳・午睡チェックを1つの園アプリにまとめる構想です。
保育士用と保護者用はアプリを分け、まず保育士用から作っています。

## いまあるもの

- **午睡チェック（保育士用 v0.3）**
  - 管理者が端末を登録し、職員は名前を選ぶだけ（午睡担当2名・①②のどちらが入力したかを記録）
  - 体位（矢印）・室温・湿度の記録、監査用の記録表の印刷
  - 園の複数のタブレットで同じ記録を共有（15秒ごとに更新）
  - Wi-Fi が切れても記録を続けられ、つながったら自動で送信
  - 設計：[docs/gosui-check-design.md](docs/gosui-check-design.md)、[docs/server-design.md](docs/server-design.md)
- **給食の未経験食材チェック（v0.1）**
  - その日の献立と、子どもごとの「家庭で食べた食材」を自動で照らし合わせ、配膳前に未経験・除去の食材がある子だけを一覧表示
  - 確認は2名で。記録には確認した時点の献立・対象の子と食材をそのまま残す
  - 設計：[docs/meal-check-design.md](docs/meal-check-design.md)

## 構成

| フォルダ | 中身 |
|---|---|
| `app/` | 画面（PWA）。ビルド不要の HTML / CSS / JavaScript |
| `worker/` | サーバー（Cloudflare Workers）。端末の登録とAPI |
| `migrations/` | データベース（Cloudflare D1）の定義 |
| `scripts/` | 園と最初の管理者を作るスクリプト |
| `tests/` | テスト（`npm test`） |

## 手元で動かす

```sh
npm install
npm run db:migrate:local
node scripts/create-facility.mjs "テスト園" admin "テスト管理者"   # 初期パスワードが表示される
npx wrangler d1 execute hoiku-tsunagu --local --file .setup/facility.sql
npm run dev        # http://localhost:8787 を開き、管理者のIDと初期パスワードで端末を登録
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
   表示された初期パスワードで端末を登録し、設定タブの管理者モードからパスワードを変更する。終わったら `.setup/` フォルダを削除する
5. `npm run deploy` で公開。表示された URL をタブレットで開き、「ホーム画面に追加」する

実在の園児の情報を入れる前に、[docs/server-design.md](docs/server-design.md) の「まだやっていないこと」を確認してください。
