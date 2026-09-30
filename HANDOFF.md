# シフトすたんぷ — Claude Code 引き継ぎメモ

保育園職員向けのシフト希望入力・確定シフト作成ツール。単一HTMLファイル（ビルド不要）＋Firebase（Firestore）構成。Claude (chat)側でここまで作ってきたものを、Claude Codeに引き継ぐ。

## 現物ファイル

- 本体：`shift-stamp.html`（このメッセージに添付。46KB前後の単一ファイル。CSSは`<style>`、JSは`<script type="module">`にすべてインライン）
- デプロイ用に中身が同一の`index.html`と、それをzip化した`shift-stamp-site.zip`も存在する（Netlify Dropへのドラッグ&ドロップ用）
- package.json・node_modules・ビルド設定は存在しない。これで完結している

## 技術構成

- フレームワークなし。素のJS。独自の軽量な `state` オブジェクト＋ `render()`（innerHTML全書き換え）というミニマムな仕組みで動いている（React等は不使用）
- バックエンドはFirebase（Firestore + 匿名認証）。CDN経由のESモジュールimportで読み込んでいる（`https://www.gstatic.com/firebasejs/12.17.1/...`）
- ホスティングはNetlify Drop（ユーザーの意向で **Cloudflareは使わない方針**）
- フォントはGoogle Fonts（Zen Maru Gothic + Noto Sans JP）

## Firebaseプロジェクト情報

- プロジェクトID: `shift-stamp`
- `firebaseConfig` は既にファイル内に埋め込み済み（167行目付近）：
  ```js
  const firebaseConfig = {
    apiKey: "AIzaSyDyWDrzX7-kewNIYTTGrpws3RpSJN0TdDQ",
    authDomain: "shift-stamp.firebaseapp.com",
    projectId: "shift-stamp",
    storageBucket: "shift-stamp.firebasestorage.app",
    messagingSenderId: "75973119685",
    appId: "1:75973119685:web:4cefe9ec38a4a3b1caaaac"
  };
  ```
  ※Web用のAPIキーなので露出しても問題ない前提（Firebaseの標準仕様。セキュリティはFirestoreルール側で担保）
- Firestoreルール（設定済みのはず）：
  ```
  rules_version = '2';
  service cloud.firestore {
    match /databases/{database}/documents {
      match /staff_requests/{docId} { allow read, write: if request.auth != null; }
      match /final_shifts/{docId} { allow read, write: if request.auth != null; }
      match /settings/{docId} { allow read, write: if request.auth != null; }
    }
  }
  ```
- Authenticationは「匿名」プロバイダのみ有効化済み（ログイン画面はなく、裏で自動サインインする仕組み）

## データモデル（Firestore）

- `staff_requests/{yearMonth}__{staffName}` → `{ name, yearMonth, days: {日番号: コード}, updatedAt }`
  - ドキュメントIDの職員名部分は `safeId()` で `/ . # $ [ ]` を `_` に置換
- `final_shifts/{yearMonth}` → `{ assignments: {職員名: {日番号: コード}}, updatedAt }`
- `settings/codes` → `{ list: [...コード文字列] }`（シフト一覧。全端末で共有・編集可能）
- 職員の名簿は存在しない。その月に一度でも入力した人が、そのままリストに現れる仕組み（表記ゆれがあると別人として扱われる点は未対応）

## 主な機能

- 職員側：名前入力（毎回自由入力、名簿なし）→ 月送り → タップ式カレンダー入力 → 自動保存（コピペ・コード共有は一切なし、Firestoreにリアルタイム保存）
- 日曜日はその職員がその月を初めて開いたときだけ自動で「公」が入る（変更可能）。**重要**：一度削除された後に再度「未入力」から自動生成されないよう `seenOnce` というガードを入れている（管理者が削除した直後に、開きっぱなしの職員側タブが自動で復活させてしまうバグをテストで発見し修正済み）
- 公休回数チェック：月9回を基準、2月だけ8回（※この「8回」は私の暫定値で、ユーザーからの正式な確認はまだ取れていない）。基準との差を職員側はバナー、管理者側は職員ごとのバッジで表示
- シフト一覧（コード種類）：B・G・C・L・公・有・B/有・G/有・C/有・特別休・忌引き が初期値。ユーザーが画面上で追加・削除でき、Firestore経由で全端末に同期される。未知のコードは名前の文字列からハッシュ計算した色にフォールバックする
- 管理者：固定PIN「2930」でゲート（ソースに平文で書いてあるだけの簡易的な制限。本物の認証ではない）
- 管理者タブ「希望の一覧」：全職員の希望をカレンダーで閲覧（日付タップで担当者一覧シート、編集不可）
- 管理者タブ「確定シフト作成」：カレンダー編集。日付タップ→担当者一覧シート→名前タップでコード選択シートが開く。「希望をコピーする」で希望→確定へ一括コピー（要確認、独自の確認モーダル使用）
- 職員側「確定シフトを見る」：確定シフトをカレンダーで閲覧（管理者側の編集がリアルタイム反映、コピペ不要）

## 重要な実装上の注意点

- **`window.confirm()` / `alert()` は使用禁止**：このプレビュー環境（サンドボックス）ではブロックされ、タップしても無反応になることが判明した。代わりに独自の確認モーダル（`askConfirm(message, callback)` → `state.confirmState` → `renderConfirmModal()`）を全箇所で使っている。これを踏襲すること
- onclick属性に動的な値を埋め込む際は必ず `attrArg()`（JSON.stringify後にHTMLエンティティエスケープ）を通すこと。生の `JSON.stringify()` を直接onclick文字列に埋め込むと二重引用符でHTML属性が壊れる（過去に実際に踏んだバグ）
- `<script type="module">` は **jsdomでは一切実行されない**（動作確認済みの既知の制約）。もしテストで自動化する場合は、import文だけを `const {...} = window.__FAKE_FB_X` に置換してクラシックスクリプトとして実行する回避策が必要（後述）

## これまでの試行錯誤（経緯・没案）

同じ轍を踏まないよう、過去にやって捨てた設計を記録しておく。

1. **v1：Claude自身の `window.storage` API** → 「Internal server error while processing action」という基盤側のエラーが継続し断念
2. **v2：手動コード方式**（`SS1-`から始まるbase64コードを生成→LINEでコピペ共有→貼り付けて取り込み。URLハッシュ`#c=...`での簡易デイープリンクも実装していた）→ LINEはHTMLファイル添付をブロックするが、コード方式自体は動いていた。ただし「コードの送信・コピーが面倒」というユーザーの要望により、Firebaseによる自動同期方式（v3・現行）に置き換えて完全に削除した

現行版（v3）にこれらの残骸コードは残っていないはずだが、念のため `SS1-` や `encodeBlob` 等の文字列がファイル内に残っていないか確認すると安心。

## テストについて

- このセッションのサンドボックスには外部ネットワーク（gstatic.com等）への接続権限がなく、実際のFirebaseに接続したE2Eテストは一度も実行できていない
- 代わりに、`<script type="module">` 内の3つのimport文だけを `window.__FAKE_FB_APP` 等への `const` 分割代入に機械的に置換し、残りのアプリコードは無改変のままNode.js + jsdomのクラシックスクリプトとして実行し、手製のインメモリFirestore/Auth模擬実装（`onSnapshot`・`setDoc`・`deleteDoc`・匿名認証のコールバック等を模擬）にぶつけてロジックを検証していた
- このテストスクリプト自体（`test_firebase.js`）はこのセッション内（`/home/claude/shifttest/`）にしか存在せず、Claude Codeの環境には引き継がれない。同等のテストが欲しい場合は同じ手法で再構築するか、実際にデプロイ済みのFirebaseプロジェクトに対して本物のブラウザ（Playwright等）でE2E検証するほうが確実
- 直近のテストは25項目全てパス（接続、認証、公休自動入力と編集、PIN認証の正誤、リアルタイム同期（職員→管理者・管理者→職員）、確認モーダル経由の一括コピー、個別編集、シフト一覧の共有編集、削除の伝播と「削除の蒸し返しバグ」の再発防止、ログアウト時の再ロック、カレンダーグリッドの構造）

## 未確認・持ち越し事項

1. **2月の公休基準「8回」は私の暫定値**。ユーザーからの正式な数字の確認が取れていない
2. **直近のカレンダー化（希望の一覧・確定シフト作成・確定シフトを見るの3画面）について、実機・実際のデプロイ環境での動作確認をユーザーからまだ受け取っていない**。このメッセージの直前に渡したばかりの状態
3. 職員名簿機能がないため、名前の表記ゆれ（スペースの有無等）で別人扱いになるリスクは未対応のまま
4. 管理者PIN「2930」は平文でソースに埋め込まれているだけの簡易的な制限。本人からは「これでよい」という明示の合意は得ているが、真のアクセス制御ではない点は継続して意識すること

## デプロイ方法

Netlify Drop（`app.netlify.com/drop`）に `index.html`（または`shift-stamp-site.zip`）をドラッグ&ドロップするだけ。アカウント登録もCLIも不要。**Cloudflareは使わない方針**なので、Cloudflare Pages/Workers等を提案しないこと。
