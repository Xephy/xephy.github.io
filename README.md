# ポケモンリボーン 日本語攻略

[BIGJRA](https://github.com/BIGJRA/BIGJRA.github.io) 氏の Pokémon Reborn 攻略を
日本語化したフォークです。公開先は <https://xephy.github.io/> 。

訳語は同じ作者による Pokémon Reborn 日本語化パッチから書き出しており、
攻略サイトとパッチで食い違わないようにしています (`_ja/README.md`)。
Rejuvenation と Desolation は日本語化していないため、ページを生成していません。

## 更新のしかた

```
_ja/changelog.yml に1行足す   # 読む側から見える変更を公開したとき
bin/ja build                  # 手元のゲームの Scripts から src/reborn.md と章ページを生成
git commit -a
git push                      # push すると Actions がビルドして公開する
```

`_ja/changelog.yml` は目次ページの「更新情報」と `/reborn/changelog/` になります。
目次の「最終更新」はビルドした時刻なので、中身が変わっていない日でも動きます。
**何が変わったのかを答えられるのは changelog だけ**なので、公開したら忘れずに
足してください。読む側から見えない変更 (計測の設定など) は載せません。

`bin/ja serve` にすると生成後にローカルサーバーが立ち上がります。
`bin/ja en` は英語版として生成し直すので、日本語化の回帰確認に使えます。

生成物 (`src/reborn.md`、`src/reborn-chapters/`、`src/reborn-mon/`、`src/reborn-move/`)
をコミットしているのは、上流のワークフローが使う非公開のゲームデータ
リポジトリに触れないためです。
CI はゲームの Scripts を持てないので、出来上がった `src/` をビルドして
配信するだけになっています。**`bin/ja build` を忘れると原稿を直しても公開
内容は変わりません。**

## 補助スクリプト

| | |
|---|---|
| `bin/ja` | 生成とローカル確認 |
| `bin/verify-chapters` | 構造・見出し・リンク・数値の照合 |
| `bin/check-terms` | 訳語をパッチの辞書と突き合わせる |
| `bin/check-rendered` | 公開ページに未訳の英語が出ていないか調べる |
| `bin/check-tracking` | 計測タグ・広告タグ・ads.txt が期待どおりか照合する |
| `bin/convert-images` | 攻略図を WebP に変換し、画素サイズ一覧を書き出す |
| `bin/gen-mon-icons` | ゲームのシートからポケモンのアイコンを切り出す |
| `bin/gen-favicon` | favicon を作る |

## 設定と方針の記録

サイトの外側（検索・計測・広告）の設定は、管理画面にしか無いと履歴も理由も残らない。
実際に、フォーク元の Google Analytics 測定 ID がおよそ2年ぶん残ったままで、
全ページのアクセスが向こうのプロパティへ送られていたことがある。
あるべき状態と判断の理由をリポジトリ側に置いてある。

| | |
|---|---|
| [`TRACKING.md`](TRACKING.md) | Google Analytics・AdSense。ID 一覧、自動広告の設定、判断の理由 |
| [`SEO.md`](SEO.md) | Search Console・サイトマップ・noindex・`_config.yml` の勘所 |

**設定を変えたら、対応する md も直すこと。** `TRACKING.md` に書いた項目のうち
コードから確かめられるものは `bin/check-tracking` が照合する（`--prod` で本番も見る）。

---

以下は上流のドキュメントです。

# BIGJRA.github.io

Welcome to the BIGJRA.github.io repository! This is my ever-evolving Pokemon Reborn, Rejuvenation, and Desolation walkthrough project, forged through years of experience with web development and learning new tips and tricks.

The project is built using Jekyll and includes scripts that generate dynamic content based on a local copy of game files - instructions for building the project are below.

There are two major steps being done in this build process:

1. Ruby-based markdown build that imports data straight from the game's files and raw walkthrough markdown files, creating `<walkthrough>.md`.
2. Jekyll converts the `<walkthrough>.md` files into browser-ready `<walkthrough>.html` files. 

## Prerequisites

Before you get started, make sure you have the following:

- **Ruby**: Installed on your machine. [Install Ruby](https://www.ruby-lang.org/en/documentation/installation/)
- **Bundler**: For managing Ruby gems. Install it with `gem install bundler`.
- **Git**: For version control and cloning repositories. [Install Git](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git)

## Preparing Walkthrough Markdown via Ruby Command

The primary Ruby script in this project, `wt_generator.rb`, generates markdown files based on the scripts and game data. You need to run this script with the appropriate arguments.

### Command Syntax

Default rake commands can be executed to easily generate markdown files: `rake generate_reborn`, `rake generate_rejuv`, `rake generate_deso` respectively. You can modify the rakefile locally if needed to change arguments for the following command syntax:

ruby wt_generator.rb <game> <scripts directory> <output file>

- `<game>`: Specify the game type (`reborn`/`rejuv`/`deso`).
- `<scripts directory>`: Path to the directory containing the scripts. This project relies on the Scripts directories - those found in the (most recent) game's files itself will work locally for most purposes.
- `<output file>`: Path to the file where the generated markdown will be saved. To serve with Jekyll later, this by default should be `./src/<game>.md`.

## Building and Running Locally

Jekyll is configured in this project to serve appropriate files in the `src` directory. To build and run the site locally, use the following commands:

1. **Install Dependencies**:

   `bundle install`

2. **Build the Jekyll Site**:

   `rake build`

3. **Serve the Site Locally**:

   `rake serve`

   Open [http://localhost:4000](http://localhost:4000) in your web browser to view the site.

## Contributing

If you want to contribute to this project, please follow the standard open-source practices: fork, create a branch, commit your changes, push, and open a pull request back to my repository. In particular, 99% of errors with walkthrough information can be solved by editing the appropriate raw markdown section in the `_raw` directory.

Please join my [Discord Server](https://discord.gg/3r83avH4sv) with any questions or for more significant contributions! Thank you.
