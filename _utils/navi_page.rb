# frozen_string_literal: true

require 'json'
require_relative 'ja_names'

# ナビ (/reborn/navi/)。
#
# 空を飛ぶを覚えるまでは、遠くへ行くのに区画をいくつも歩いて抜けることになる。
# 出発地と目的地を選ぶと、歩いて行く道をゲームの地図の上に引いて見せる。
#
# 道はサイトの生成側では探さない。bin/navi-build がゲームのマップデータと
# 進み具合 (_ja/navi/states/) から探して src/assets/navi/ に書き出したものを、
# ページの navi.js が読む。ここで組むのは入れ物と、選べる進み具合の一覧だけ。
module NaviPage
  module_function

  STATES_DIR = File.expand_path('../_ja/navi/states', __dir__)
  DATA_DIR = File.expand_path('../src/assets/navi', __dir__)
  CHAPTERS = 19

  def esc(text)
    text.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;').gsub('"', '&quot;')
  end

  # 道のデータまでそろっている進み具合。キーは ch<章>。
  def states
    Dir[File.join(STATES_DIR, '*.json')].filter_map { |f|
      key = File.basename(f, '.json')
      next unless File.exist?(File.join(DATA_DIR, "#{key}.json"))

      j = JSON.parse(File.read(f))
      { key: key, chapter: key[/\d+/].to_i, label: j['label'], badges: j['badges'] }
    }.sort_by { |s| s[:chapter] }
  end

  def options(ready)
    by_ch = ready.to_h { |s| [s[:chapter], s] }
    (1..CHAPTERS).map { |n|
      if by_ch[n]
        %(<option value="#{esc(by_ch[n][:key])}" data-badges="#{by_ch[n][:badges]}">#{n}章まで終えた</option>)
      else
        %(<option disabled>#{n}章まで終えた（準備中）</option>)
      end
    }.join
  end

  def build_page(game)
    ready = states
    return nil unless JaNames.enabled? && !ready.empty?

    first = ready.first[:key]   # 初めて開いたときの進み具合 (いちばん早い章)。2回目からは前に選んだ章
    <<~PAGE
      ---
      title: ナビ（β版）
      permalink: /#{game}/navi/
      description: "ポケモンリボーンで、出発地から目的地まで歩いて行く道を地図で案内します。進み具合ごとに通れる道で探します。"
      ---

      <p id="title-text">ナビ（β版）</p>

      <p class="ref-back"><a href="/#{game}/">#{JaNames.ui('Back to contents')}</a></p>

      出発地と目的地を選ぶと、歩いて行く道を地図で案内します。通れる道は物語の進み具合で変わるので、何章まで進めたかも選んでください。

      出発地と目的地は、その場所のポケモンセンターの前です。ポケモンセンターの無い場所は、その場所の入口にしています。空を飛ぶ・ロッククライム・かいりき・ダイビングを使う道は案内しません。

      <div class="navi" id="navi" data-base="/assets/navi/" data-default="#{esc(first)}">
      <div class="navi-panel">
      <div class="navi-form">
      <label class="navi-field"><span>進み具合</span><select id="navi-prog">#{options(ready)}</select></label>
      <label class="navi-field navi-from"><span>出発地</span><select id="navi-from" disabled><option>読み込み中…</option></select></label>
      <label class="navi-field navi-to"><span>目的地</span><select id="navi-to" disabled><option>読み込み中…</option></select></label>
      <div class="navi-row"><button type="button" id="navi-swap" class="navi-swap" title="出発地と目的地を入れ替える">⇅ 入れ替え</button><button type="button" id="navi-go" class="navi-go">ナビ開始</button></div>
      <p class="navi-msg" id="navi-msg" role="status"></p>
      </div>
      <div class="navi-summary" id="navi-summary" hidden></div>
      <ol class="navi-steps" id="navi-steps"></ol>
      </div>
      <div class="navi-map" id="navi-map">
      <div class="navi-hint" id="navi-hint">ここに地図と道筋が出ます</div>
      <div class="navi-stage" id="navi-stage"><div class="navi-world" id="navi-world"></div></div>
      <div class="navi-banner" id="navi-banner" hidden></div>
      <div class="navi-mapname" id="navi-mapname" hidden></div>
      <div class="navi-stepnav" id="navi-stepnav" hidden><button type="button" id="navi-prev">前へ</button><button type="button" id="navi-next" class="is-primary">次へ</button></div>
      <div class="navi-ctrl"><button type="button" id="navi-zin" aria-label="拡大">＋</button><button type="button" id="navi-zout" aria-label="縮小">－</button><button type="button" id="navi-fit" aria-label="いまの区間に合わせる">◎</button></div>
      </div>
      </div>

      <script src="/assets/js/navi.js" defer></script>
    PAGE
  end
end
