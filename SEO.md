# 検索に載せるための設定

このサイトを Google 検索に出すための仕組みと、そう決めた理由。
計測タグと広告については `TRACKING.md` を見る。

ビルドの `source` は `./src` なので、このファイルは公開されない。

---

## 前提

- 公開先 <https://xephy.github.io/>
- Search Console には **URL プレフィックス プロパティ** `https://xephy.github.io/` を登録
- **所有権の確認は HTML ファイル方式**

### 所有権確認ファイルを壊さないこと

`src/google648e807086f5cb1a.html`（54 バイト）は Google が指定した1行だけを持つ静的ファイル。

- **消すと所有権の確認が外れ、Search Console が使えなくなる**
- **front matter を付けない。** 付けると layout が被さって確認に通らなくなる
- `_config.yml` の `defaults` で `sitemap: false` にして、サイトマップからは外している

`github.io` は Public Suffix List に載っているので、このサイトから見た「ルートドメイン」は
`xephy.github.io` そのもの。確認ファイルも `ads.txt` も、ここの直下に置くのが正しい。

---

## サイトマップ

- `jekyll-sitemap` が `/sitemap.xml` を生成する。**GitHub Pages では既定で有効にならない**ので
  `_config.yml` の `plugins` に明示してある
- `src/robots.txt` から `Sitemap: https://xephy.github.io/sitemap.xml` で参照している
- 現在 847 URL（`bin/check-tracking` が件数と中身を確認する）

トップページからのリンクだけでは 850 ページ全部は辿ってもらえないので、サイトマップは要る。
ただし**サイトマップが読めなくてもインデックス登録自体は進む。** 焦らないこと。

### 2026-08-27 の切り分け（記録）

Search Console が「取得できませんでした」のまま動かなかったときに調べたこと。
**ファイル側は全項目シロだった**ので、同じ症状が出たらファイルを疑う前にここを読む。

- URL 検査の「公開 URL をテスト」は **「URL は Google に登録できます」** = Googlebot は取得できている
- ファイルは 200 / `application/xml` / BOM 無し / XML パース OK / 全 URL が `https://xephy.github.io` /
  Googlebot の UA でも 200
- 打ち間違いでありがちなパスは全部 404（`/sitemap.xml/`、`/sitemap_index.xml`、`/sitemap.XML`、URL 二重）。
  通るのは `/sitemap.xml` のみ
- `<lastmod>` は1つも無いが、仕様上は任意

結論として Search Console 側の問題と判断し、**登録を削除して同じ URL で送信し直した。**

---

## 検索結果に出さないページ

`<meta name="robots" content="noindex, follow">` を付けているのは2ページだけ。

| ページ | 実体 | 理由 |
| --- | --- | --- |
| `/reborn/all/` | `src/reborn.md` | 全文1ページ。約 14.7 MB あり、章ページ 28 本と本文が完全に重複する |
| `/404.html` | `src/404.html` | 中身はトップへ飛ばすだけ |

どちらも front matter に **`noindex: true`（または直接 `<meta>`）と `sitemap: false` の両方**を付けてある。
`noindex: true` を拾って `<meta name="robots" content="noindex, follow">` を出すのは
`src/_layouts/default.html`。`follow` は付けたままなので、**ここからのリンクは辿られる。**

読む人向けには全文ページを残したいが、検索では章ページと競合させたくない、という判断。
**1ページ版のほうを検索に出したくなったら、逆にする。**

なお `/404.html` を直接開くと 200 が返るが、存在しない URL 経由なら**ちゃんと 404 が返る**（実測）。

---

## 導入ページ `/patch/` の狙い

日本語化パッチ本体は別リポジトリ（後述）だが、**GitHub のリポジトリページを検索に載せるより、
攻略サイト側にパッチの導入ページを作ってそこから流すほうが上げやすい。**
`src/patch.md` がそれで、**トップページ（`src/index.md`）から4か所、
攻略の目次（`src/reborn-chapters/contents.md`）から1か所**リンクしてある。

**GitHub と Qiita からのリンクは `nofollow`** なので、検索順位には効かない。
人が辿る導線としてだけ数えること。

---

## `_config.yml` の勘所

うっかり壊しやすいところ。

- **`url:`** … `jekyll-seo-tag` が canonical と `og:url` を組み立てるのに使う。
  設定しないと手元のビルドが `http://localhost:4000` を canonical に書き、
  その `_site` をそのまま配ると**検索エンジンに存在しない URL を教えることになる**
- **`tagline:`** … トップの `<title>` は「サイト名 \| ここ」の形になる。
  tagline が無いと `description` が丸ごと題に入って長すぎる題になる
- **`description:`** … 検索結果のスニペットになる。各ページに description が無いときの既定値。
  **折り返すと改行がそのまま空白になり、日本語の文中に空白が入る。1行で書く**
- **`lang: ja`** … `<html lang>` と `og:locale`。既定は `en-US` で、日本語のページに英語を宣言していた

---

## 日本語化パッチ側のリポジトリ

<https://github.com/Xephy/reborn-19.5.43-ja>（既定ブランチは `master`。
手元の clone は `~/dev/reborn-dev/reborn-19.5.43-ja`）

**github.com は自分の持ち物ではないので Search Console に登録できない。** 触れるのは次だけ。

- **リポジトリの説明文** … これがブラウザの `<title>` になる。カタカナ「ポケモンリボーン」を入れてある
- **README の冒頭** … 元はカタカナ表記が0回で、検索語と一致していなかった
- **Topics**
- **About の Website** … `https://xephy.github.io/patch/` を設定済み

---

## 次に見るとき

- Search Console のサイトマップが「成功しました」に変わったか
- 「ページ」レポートでインデックス登録済みの件数が伸びているか
- インデックス登録を個別にリクエストしたのは6本
  （トップ、`/reborn/`、`/reborn/mon/`、`/reborn/pokemon/`、`/reborn/episode-1/`、`/patch/`）
