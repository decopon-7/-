# サムネイル計画(初期20本 カット出し)

[content-calendar.md](./content-calendar.md)の初期20本について、[channel-strategy.md](./channel-strategy.md) §5のサムネイルルール(「表情がはっきり分かるキャラクターの顔+短い訴求テキスト(3〜5文字)。シリーズごとに色帯を統一しブランド認知を作る」)に沿ってカットを出し、実際のサムネイル画像を`assets/thumbnails/`に生成した。

## ステータス

現バージョンは、確定ポーズ集([character-design.md §6](./character-design.md#6-追加ポーズ生成済み確定))にある5種類のポーズを使い回した**プレースホルダー版**。動画ごとの厳密な内容とポーズが一致していないものも含む(例: 「てあらい」に万歳ポーズを使用等)。撮影・編集が具体化した段階で、動画の実際のハイライトシーンに差し替える。

## シリーズカラー(サムネイル背景帯)

| シリーズ | カラー | HEX |
|---|---|---|
| せいかつしゅうかん | オレンジ | `#FF9D5C` |
| ことばとうた | イエロー | `#FFD166` |
| かず・かたち | スカイブルー | `#8FB8DE` |
| きもちのじかん | ミントグリーン | `#7DC9A7` |
| しぜんとはっけん | テラコッタ | `#C97B4A` |
| ほいくしのワンポイント | セージグリーン | `#A9C5A0` |

[character-design.md](./character-design.md)のキャラクターパレットと同系統の色を使い、キャラクター・サムネイル・ランディングページ全体でブランドの一貫性を保つ。

## カット出し一覧

| No. | シリーズ | タイトル(案) | サムネ文言 | 使用ポーズ | ファイル |
|---|---|---|---|---|---|
| 1 | せいかつしゅうかん | 保育士が教える手洗いソング | てあらい | tanechan-banzai | [01.jpg](../assets/thumbnails/01.jpg) |
| 2 | せいかつしゅうかん | はみがきレッスン | はみがき | tanechan-toothbrush(完全一致) | [02.jpg](../assets/thumbnails/02.jpg) |
| 3 | ことばとうた | おててをたたきましょう手遊び歌 | おてて | tanechan-banzai | [03.jpg](../assets/thumbnails/03.jpg) |
| 4 | ことばとうた | あいさつうた | あいさつ | tanechan-wave(完全一致) | [04.jpg](../assets/thumbnails/04.jpg) |
| 5 | きもちのじかん | クールダウン呼吸法 | すーはー | tanechan-breathing(完全一致) | [05.jpg](../assets/thumbnails/05.jpg) |
| 6 | かず・かたち | 1から5までかぞえてみよう | かぞえよう | tanechan-thinking | [06.jpg](../assets/thumbnails/06.jpg) |
| 7 | かず・かたち | まるさんかくしかく なかまさがし | なかまさがし | tanechan-thinking | [07.jpg](../assets/thumbnails/07.jpg) |
| 8 | せいかつしゅうかん | おきがえバッチリ選手権 | おきがえ | tanechan-banzai | [08.jpg](../assets/thumbnails/08.jpg) |
| 9 | しぜんとはっけん | おそとであきをみつけよう | あきみつけ | tanechan-wave | [09.jpg](../assets/thumbnails/09.jpg) |
| 10 | ほいくしのワンポイント | 「イヤイヤ期」との向き合い方 | イヤイヤ期 | midori-sensei-talking(完全一致) | [10.jpg](../assets/thumbnails/10.jpg) |
| 11 | ことばとうた | おなまえよんで！はーい手遊び | おへんじ | tanechan-wave(完全一致) | [11.jpg](../assets/thumbnails/11.jpg) |
| 12 | きもちのじかん | ともだちとなかよく | なかよく | tanechan-banzai | [12.jpg](../assets/thumbnails/12.jpg) |
| 13 | せいかつしゅうかん | トイレさん、こんにちは | といれ | tanechan-wave | [13.jpg](../assets/thumbnails/13.jpg) |
| 14 | かず・かたち | おおきい・ちいさい くらべっこ | くらべっこ | tanechan-thinking | [14.jpg](../assets/thumbnails/14.jpg) |
| 15 | しぜんとはっけん | みずのあそび、ひえひえ・あったか | みずあそび | tanechan-banzai | [15.jpg](../assets/thumbnails/15.jpg) |
| 16 | ことばとうた | どうぶつのなきまねうた | なきまね | tanechan-wave | [16.jpg](../assets/thumbnails/16.jpg) |
| 17 | きもちのじかん | どきどきしたときのおまじない | どきどき | tanechan-breathing(完全一致) | [17.jpg](../assets/thumbnails/17.jpg) |
| 18 | せいかつしゅうかん | あさのおしたく、じぶんでできるよ | おしたく | tanechan-toothbrush | [18.jpg](../assets/thumbnails/18.jpg) |
| 19 | ほいくしのワンポイント | 「発達が気になる」ときの相談先ガイド | そうだん | midori-sensei-pot | [19.jpg](../assets/thumbnails/19.jpg) |
| 20 | かず・かたち | すうじのうた 1〜10 | すうじのうた | tanechan-banzai | [20.jpg](../assets/thumbnails/20.jpg) |

## レイアウト仕様

- 解像度: 1280×720(YouTube標準)
- 左側: シリーズカラーの単色背景 + 太字テロップ(白文字+ダークブラウン#3A2E26のアウトライン、視認性優先)
- 右側: オフホワイト角丸パネル上にキャラクターポーズを配置
- 左下: シリーズ名の小さなピルバッジ

## 今後のTODO

- [ ] 撮影・編集が固まった動画から、実際のハイライトシーンの表情に差し替える(現状は5ポーズの使い回し)
- [ ] タイトルの検索需要語(「〇歳児向け」等)をサムネ本体ではなく動画タイトル側で担保しているか、A/Bテストで確認する([channel-strategy.md](./channel-strategy.md) §5参照)
- [ ] サムネ文言が3〜5文字を超えているもの(なかまさがし・すうじのうた等)は、視認性を見ながら短縮を検討する
