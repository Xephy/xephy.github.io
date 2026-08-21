# 本文の訳語メモ

`bin/check-terms` は `_ja/dict.json` に載っている語しか検証できません。辞書は
ゲームのデータ定義（`montext.rb` / `itemtext.rb` / `20_map_names.jsonl` など）から
作っているため、**NPC のセリフの中にしか出てこない呼び名は含まれません**。

そういう語は `bin/check-terms --unknown <英語版>` で候補を洗い出し、
`bin/find-term "<英語>"` で会話データを当たって決めます。決めた結果をここに残します。

```
bin/check-terms --unknown /tmp/ep05_en.md   # 辞書で引けない固有名詞を列挙
bin/find-term "Team Meteor"                 # 会話データから対訳を探す
```

## 会話データで裏を取った語

| 英語 | 訳 | 出典・注記 |
|---|---|---|
| Team Meteor | チームメテオ | 会話では「チームメテオ」が主。トレーナー種別だけ「メテオだんしたっぱ」 |
| Cocoon Badge | まゆバッジ | バッジ18個のうち4個は和語（ごうきん／まゆ／しもの／げきりゅう） |
| Department Store Sticker | デパートシール | 取得メッセージより。「デパートのシール」ではない |
| Mystery Egg | 謎のタマゴ | 交換メッセージより |
| Voltorb Flip | ビリリダマフリップ | ゲーム内表記 |
| Madame Meganium | メガニウム夫人 | 「マダム・メガニウム」ではない |
| Lykos | ライコス | 「リュコス」ではない |
| Critical Capture | クリティカルキャプチャー | 店名として会話に登場 |
| Light Shard | 光のかけら | |
| Seacrest's Garden | シークレストの庭 | |
| Bouffalant Bill | バッフロンビル | |

## ゲームに存在しない、攻略側の造語

原文の著者が独自に付けた呼び名です。会話データを探しても出てきません。

| 英語 | 訳 | 判断の理由 |
|---|---|---|
| (X Field) Readout | 〜の資料 | ゲーム内に該当語なし。アプリ名「フィールドノート」と区別するため「資料」を当てた |
| Default Mart | 標準ショップ | 原文の "Default Shops" の説明に対応 |
| Devon Dungeon | デボンコーポ地下 | ゲームのマップ名「デボンコーポ地下1階」に寄せた |
| Snooze（技教え人の渾名） | スヌーズ | 看板の駄洒落 "You Snooze, You Moves"（うかうかしてると技を逃す）由来。人名としては未登場 |

## 表と本文で表記を変えているもの

ゲーム内の表記はかな中心ですが、本文では読みやすさを優先しています。
理由は `_ja/term-exceptions.yml` に記録してあります。

| 表（自動生成） | 本文（手訳） |
|---|---|
| けいかん | 警官 |
| ジェントルマン | 紳士 |
| アクアだんいん / マグマだんいん | アクア団 / マグマ団 |
| かんごにん | 看護人 |

## 章タイトルの訳（確定）

英語のタイトルには言葉遊びや章どうしの対応が仕込まれているため、逐語訳では落ちます。
以下は内容を確認したうえで確定させたものです。**翻訳時はこの表に従ってください。**

| # | 原文 | 訳 | 判断 |
|---|---|---|---|
| 1 | Reborn, the City of Ruin | リボーン、廃墟の街 | 16話と対の額縁構造。名前を先に置いて「再生という名の廃墟」の皮肉を立てる |
| 2 | Reap What's Been Sewn | 蒔いた種は刈り取るもの | 原文は `sown`→`sewn` の駄洒落だが、攻略記事の読みやすさを優先して意味を取る |
| 3 | Domino | ドミノ | |
| 4 | Aftershocks | 余震 | 地震の余震と事件の余波、両義が生きる |
| 5 | Escape! from Reborn City | リボーンシティ脱出! | 原文の語順に引きずられないこと |
| 6 | Poison In Vein | 血に毒を | 7話と同音（ちにどくを）。漢字1字だけ違う＝原文の Vein/Vain と同じ仕掛け |
| 7 | Poison In Vain | 地に毒を | 舞台のビクシビョン荒野＝毒に灼かれた地 |
| 8 | Of Fathers Forgotten | 忘れられし父たち | 原文の古風な倒置に「し」で応じる |
| 9 | Sister's Keeper | 妹の番人 | 創世記「わたしは弟の番人でしょうか」の型 |
| 10 | Into Darkness | 闇の中へ | 11話と対 |
| 11 | Out of Light | 光の外へ | Into / Out of を「中へ」「外へ」で保存 |
| 12 | Demarcation | 一線を越えて | この章以降、約4バッジ分ぶん過去エリアへ戻れなくなる。不可逆性を汲んだ意訳 |
| 13 | Cascade | 奔流 | なみのり解禁の章。流れの勢いを取る |
| 14 | //outlier.corruption | //outlier.corruption | ログ調の表記自体が演出。訳さない |
| 15 | Never After | めでたくもなし | `happily ever after` の否定。フィオレ邸＝おとぎ話がテーマの章 |
| 16 | A City, Reborn | リボーン、よみがえる街 | 1話と対 |
| 17 | Rust Thicker Than Water | 錆は水よりも濃し | 「血は水よりも濃し」の血を錆に置換 |
| 18 | Void-Kissed | 虚無の口づけ | |
| 19 | Pokemon Reborn | ポケモンリボーン | 作品名 |

| ポストゲーム | 原文 | 訳 |
|---|---|---|
| 1 | A Whole New World | まっさらな新世界 |
| 2 | Fetch, Doggy! | 取ってこい、ワンちゃん! |
| 3 | The Umbral Issue | 影の一件 |
| 4 | Across Space & Time | 時空を越えて |
| 5 | Wish Upon a Star | 星に願いを |
| 6 | Lights Out | 消灯 |
| 7 | Up, Down, n' All Around | 上へ下へ、そこらじゅう |
| 8 | A Canvas of Cyclical Conflict | 巡る争いのカンバス |
| 9 | Pokemon Reborn, Reborn! | ポケモンリボーン、リボーン! |
| — | Appendices | 付録 |
