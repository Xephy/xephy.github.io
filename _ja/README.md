# `_ja/` — 日本語化データ

## dict.json は生成物です

直接編集しないでください。日本語化パッチ側のツールが書き出しています。

```
cd ../Reborn-19.5.0-windows
python3 jp_translation/tools/export_web_dict.py
```

訳を直したいときは、パッチ側の `jp_translation/work/` を直してから
上記を再実行してください。

## 訳文の出どころ

`dict.json` に入っている訳文は、同じ作者による Pokémon Reborn 日本語化パッチ
から書き出したものです。攻略サイトとパッチで訳語が食い違わないよう、
パッチ側を唯一の出典として扱っています。

ポケモンの名称・技名・道具名などの原語は任天堂／株式会社ポケモン／
ゲームフリーク／クリーチャーズの著作物です。詳細はパッチ側の `NOTICE` を
参照してください。

## 生成側での使われ方

`_utils/ja_names.rb` が読み込みます。`WT_LANG=en` を付けて実行すると、
辞書があっても英語版として生成されます。

```
WT_LANG=en ruby wt_generator.rb reborn <Scripts> src/reborn.md
```
