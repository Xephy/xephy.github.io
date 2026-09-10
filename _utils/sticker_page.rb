# frozen_string_literal: true

require 'cgi'
require 'json'
require_relative 'ja_names'
require_relative 'machine_index'

# デパートステッカー。
#
# オブシディア区のデパートは、メンバーズカードに貼ったステッカーの枚数だけ
# 上の階へ行ける。枚数と階の対応、11枚の配り手、最上階の品ぞろえはどれも
# マップのイベントにしか無い。サイトの生成側は .rxdata を読まないので、
# 日本語化パッチの export_stickers.py が拾った _ja/stickers.json を読む。
#
# 入手の場面は攻略本文へのリンクで示す。本文はステッカーを
# 「デパートステッカー「○○」」と書いていて、ゲームの入手メッセージと同じ形。
module StickerPage
  module_function

  DATA_PATH = File.expand_path('../_ja/stickers.json', __dir__)

  # 序盤のペリドット区で取り逃したときの代わり。Map537 の人物は、ジャスパー区で
  # 友人を助けていない (スイッチ88 が OFF) ときだけネオリボーンシティに現れ、
  # 同じスイッチ1089 を立てる。ペリドット区の人物はスイッチ88 が ON のときだけ渡す。
  CATCH_UP = { 'TANGELA' => 'ジャスパー区で友人を助けないまま進めた場合、' \
                            'このステッカーはペリドット区ではもらえません。' \
                            '後半のネオリボーンシティのジャスパー区で、同じ1枚をもらえます。' }.freeze

  def data
    @data ||= File.exist?(DATA_PATH) ? JSON.parse(File.read(DATA_PATH)) : nil
  end

  def esc(text)
    text.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;').gsub('"', '&quot;')
  end

  def species_name(sym, pokemon_hash)
    forms = pokemon_hash[sym.to_s.to_sym]
    base = forms && forms.keys.find { |k| k.is_a?(String) }
    base ? forms[base][:name] : sym.to_s
  end

  def chapter_label(title)
    m = title.to_s.match(/\A(.+?)[:：]/)
    m ? m[1].strip : title.to_s.strip
  end

  # 「1階 - 低ランク一般; 薬品」を階と売り場に分ける。最上階は売り場の名前が無い。
  def split_floor(label)
    floor, section = label.to_s.split(/\s+-\s+/, 2)
    [floor.to_s.strip, section.to_s.strip]
  end

  def floor_rows(floors, game)
    floors.map do |f|
      floor, section = split_floor(f['label_ja'])
      # 1〜11階は店の索引に「デパート9階（右）」の形で載っている。最上階は
      # 本文に出てこないので載っておらず、品ぞろえはこのページの下に出す。
      name =
        if section.empty?
          %(<a href="#penthouse">#{esc(floor)}</a>)
        else
          %(<a href="/#{game}/shops/?q=#{CGI.escape("デパート#{floor}")}">#{esc(floor)}</a>)
        end
      %(<tr><td class="stk-floor">#{name}</td><td>#{esc(section.empty? ? '—' : section)}</td>) +
        %(<td class="stk-num">#{f['stickers']}枚</td></tr>)
    end.join
  end

  def sticker_rows(stickers, places, pokemon_hash, map_hash)
    stickers.each_with_index.map do |s, i|
      name = species_name(s['species'], pokemon_hash)
      where = s['maps'].map { |id| map_hash[id] }.compact.uniq
      where = ['メンバーズカードに最初から付いている'] if s['card']
      links = places[s].map { |p|
        %(<li><a href="#{p[:href]}">#{esc(p[:text])}</a> <span class="tm-meta">#{esc(chapter_label(p[:chapter]))}</span></li>)
      }
      note = CATCH_UP[s['species']]
      %(<tr><td class="stk-num">#{i + 1}</td><td class="stk-name"><strong>#{esc(name)}</strong></td>) +
        %(<td>#{esc(where.join('・'))}#{note ? %(<p class="stk-note">#{esc(note)}</p>) : ''}</td>) +
        %(<td class="tm-where">#{links.empty? ? '—' : "<ul>#{links.join}</ul>"}</td></tr>)
    end.join
  end

  def penthouse_rows(items, item_hash)
    items.map do |sym|
      item = item_hash[sym.to_sym] || {}
      price = item[:price].to_i.positive? ? "$#{item[:price]}" : '—'
      %(<tr><td>#{esc(item[:name] || sym)}</td><td class="stk-num">#{price}</td></tr>)
    end.join
  end

  def build_page(game, chapters, pokemon_hash, item_hash, map_hash)
    return nil unless JaNames.enabled? && data

    labels = data['stickers'].to_h { |s| [s, "デパートステッカー「#{species_name(s['species'], pokemon_hash)}」"] }
    found = MachineIndex.locations(chapters, game, labels.values)
    places = labels.transform_values { |label| (found[label] || {}).values }

    # 本文に出てくる順 (= 集める順) に並べる。本文に無いものは後ろへ。
    order = chapters.each_with_index.to_h { |c, i| [c[:title], i] }
    stickers = data['stickers'].sort_by.with_index do |s, i|
      [places[s].map { |p| order[p[:chapter]] || 999 }.min || 999, i]
    end

    total = stickers.size
    top = data['floors'].last

    <<~PAGE
      ---
      title: デパートステッカー
      permalink: /#{game}/stickers/
      description: "ポケモンリボーンのデパートステッカー#{total}枚の入手場所と、枚数ごとに行けるデパートの階・売り場の一覧。"
      ---

      <p id="title-text">デパートステッカー</p>

      <p class="ref-back"><a href="/#{game}/">#{JaNames.ui('Back to contents')}</a></p>

      オブシディア区のデパートでは、メンバーズカードに貼ったステッカーの枚数だけ、上の階で買い物ができます。全#{total}枚で、そろえると#{esc(split_floor(top['label_ja'])[0])}まで行けます。

      ## 枚数と行ける階 {#floors}

      階の名前を押すと、その階で買えるものが出ます。

      <table class="stk-table">
      <thead><tr><th>階</th><th>売り場</th><th>必要な枚数</th></tr></thead>
      <tbody>#{floor_rows(data['floors'], game)}</tbody>
      </table>

      ## ステッカーの入手場所 {#stickers}

      <table class="stk-table">
      <thead><tr><th></th><th>ステッカー</th><th>もらえる場所</th><th>本文</th></tr></thead>
      <tbody>#{sticker_rows(stickers, places, pokemon_hash, map_hash)}</tbody>
      </table>

      ## 最上階の店 {#penthouse}

      <table class="stk-table">
      <thead><tr><th>品名</th><th>値段</th></tr></thead>
      <tbody>#{penthouse_rows(data['penthouse_items'], item_hash)}</tbody>
      </table>
    PAGE
  end
end
