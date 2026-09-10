# frozen_string_literal: true

require 'cgi'
require 'json'
require_relative 'ja_names'
require_relative 'machine_index'
require_relative 'shop_index'
require_relative 'spoiler'

# デパートステッカー。
#
# オブシディア区のデパートは、メンバーズカードに貼ったステッカーの枚数だけ
# 上の階へ行ける。枚数と階の対応、11枚の配り手、最上階の品ぞろえはどれも
# マップのイベントにしか無い。サイトの生成側は .rxdata を読まないので、
# 日本語化パッチの export_stickers.py が拾った _ja/stickers.json を読む。
#
# 1〜11階の品ぞろえは店の索引 (ShopIndex) から引く。本文の店の表から
# 組まれたもので、名前と値段が /reborn/shops/ と一致する。
module StickerPage
  module_function

  DATA_PATH = File.expand_path('../_ja/stickers.json', __dir__)
  FLOOR_SHOP = /\Aデパート(\d+)階（[左右]）\z/.freeze

  # 入手の手順。Pokémon Reborn Wiki の Department Store Stickers Sidequests と
  # 各ステッカーの個別ページを下敷きに、ゲームのイベントと本文で確かめた
  # ことだけを書いている。場所・人物・道具の名前は本文とパッチの訳に揃える。
  #
  # 数字を書いたものの出どころ:
  #   ポリゴンZ の3連戦 … Map460 EV009 の pbTrainerBattle が3回
  #   ライボルトの番号  … 本文18章にそのまま出てくる (隠していない)
  # イーブイの金庫の番号は、本文19章でネタバレとして隠しているので書かない。
  HOWTO = {
    'PORYGON' => 'オブシディア公園でゼルに勝つと、デパートに入れるようになります。' \
                 'エレベーターの横か中にいる店員に話しかけると、メンバーズカードと一緒にもらえます。',
    'TANGELA' => 'マルコウス森林公園でタカと PULSE モジャンボを倒したあと、' \
                 'ジャスパー区の集合住宅の最上階に閉じ込められている女性を助けます。' \
                 'ペリドット区の家にいる彼女の友人に話しかけるともらえます。',
    'DRIFLOON' => 'ラピス区の家で、息子がいなくなった母親の話を聞きます。' \
                  '廃発電所でフワンテに襲われている男の子を助け、さらにジャスパー区で' \
                  'ペンドラーとフシデに囲まれているところも助けると、母親からもらえます。',
    'ARON' => 'シェリーに勝って いわくだき を手に入れたら、オブシディアスラムから地下鉄道網に入り、' \
              '奥で倒れている男性を見つけます。オブシディア区のポケモンセンターへ移った彼に' \
              '話しかけるともらえます。',
    'MEDITITE' => 'アポフィルアカデミーの寮にいる生徒が、部屋にテレビを欲しがっています。' \
                  '校舎にある共用のテレビを持ち出そうとすると別の生徒とのバトルになり、' \
                  '勝って部屋へ届けるともらえます。',
    'CHANSEY' => 'スピネルタウンのベンチに座っている女性に話しかけて離れると、テレポートで飛ばされてしまいます。' \
                 'クリソリアの森で足をけがしている彼女に やくそうエキス を渡すともらえます。',
    'HERACROSS' => '1番道路のネイチャーセンター2階に、めがねをなくした男性がいます。' \
                   '南アベンチュリンの森で テックグラス を見つけて渡すともらえます。',
    'CLEFAIRY' => 'アゲートサーカス検問所の1階に、迷子の男の子がいます。' \
                  'わたあめ・ふうせん・ピッピにんぎょう を順に渡すと、母親が現れて謝り、' \
                  'おわびにもらえます。ピッピにんぎょう はサーカスのゲームの景品です。',
    'PORYGONZ' => 'アメトリンシティのポケモンセンターの近くの家にいる老人の頼みで、' \
                  'コンピューターのウイルスとグリッチフィールドで3連戦します。勝つともらえます。',
    'MANECTRIC' => 'アゲートシティのポケモンセンターの右の建物にいる女性が、前の住人の' \
                   'パソコンのパスワードを探しています。本文の手順で見つかる番号「139749」を伝えると' \
                   '隠し部屋が開き、ライボルトナイト と一緒にもらえます。',
    'EEVEE' => 'ラブラドラの右下の建物で2つ目のパスワードを入力すると、' \
               'リボンのくびわ を持ったニンフィアがもらえます。ジャスパー区の集合住宅の' \
               '2階2号室でサーナイトの話を聞いたあと、くびわ をロッティに渡すともらえます。'
  }.freeze

  # 取り逃したときの代わり。物語の後半 (リボーンシティの復興) に触れるので、
  # 本文と同じネタバレの開閉に入れる。どれもイベントの出現条件で確かめてある。
  #   モンジャラ … Map537 は友人を助けていない (スイッチ88 OFF) ときだけ現れ、同じスイッチ1089 を立てる
  #   フワンテ   … Map169 EV005 の3ページ目は復興 (スイッチ479) だけを条件に配る
  #   ココドラ   … Map083 EV013 の2ページ目は再建の全額寄付 (スイッチ652, 大ホール) で配る
  CATCH_UP = {
    'TANGELA' => '女性を助けないまま進めた場合は、後半のネオリボーンシティのジャスパー区で、同じ1枚をもらえます。',
    'DRIFLOON' => 'リボーンシティが復興してからは、男の子を助けていなくても、母親に話しかけるだけでもらえます。',
    'ARON' => '大ホールで地下鉄道網の再建に全額寄付した場合も、再建作業で救われた彼から、ポケモンセンターでもらえます。'
  }.freeze

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

  # 店の索引から、階ごとの品ぞろえ。同じ表が複数の章に出てくるので、
  # 階と品名の組で1回だけ数える。並びは本文の表のまま (左の売り場、右の売り場)。
  def floor_items
    out = Hash.new { |h, k| h[k] = [] }
    seen = {}
    ShopIndex.entries.each do |e|
      m = e[:shop].to_s.match(FLOOR_SHOP) or next
      key = [m[1].to_i, e[:item]]
      next if seen[key]

      seen[key] = true
      out[m[1].to_i] << { name: e[:item], price: e[:price] }
    end
    out
  end

  def penthouse_items(item_hash)
    data['penthouse_items'].map do |sym|
      item = item_hash[sym.to_sym] || {}
      { name: item[:name] || sym, price: item[:price].to_i.positive? ? "$#{item[:price]}" : '—' }
    end
  end

  def sticker_html(sticker, number, places, pokemon_hash)
    key = sticker['species']
    name = species_name(key, pokemon_hash)
    where = places.map { |p|
      %(<a href="#{p[:href]}">#{esc(p[:text])}</a> <span class="tm-meta">#{esc(chapter_label(p[:chapter]))}</span>)
    }.join('、')
    note = CATCH_UP[key]
    spoiler =
      if note
        %(<div class="spoilerText" style="display:none"><p>#{esc(note)}</p></div>) +
          %(<a display="initial" class="spoilerBtn" type="button">取り逃したとき</a>)
      else
        ''
      end

    <<~ITEM
      <section class="stk-item" id="stk-#{key.downcase}">
        <h3><span class="stk-no">#{number}</span>#{esc(name)}</h3>
        #{where.empty? ? '' : %(<p class="stk-where">#{where}</p>)}
        <p>#{esc(HOWTO[key])}</p>
        #{spoiler}
      </section>
    ITEM
  end

  def floor_html(floor, index, items)
    name, section = split_floor(floor['label_ja'])
    need = index.zero? ? '最初から' : "ステッカー#{floor['stickers']}枚"
    rows = items.map { |i| %(<tr><td>#{esc(i[:name])}</td><td class="stk-price">#{esc(i[:price])}</td></tr>) }.join

    <<~FLOOR
      <details class="stk-floor">
        <summary><span class="stk-f">#{esc(name)}</span><span class="stk-sec">#{esc(section)}</span><span class="stk-need">#{need}</span></summary>
        <table class="stk-table"><tbody>#{rows}</tbody></table>
      </details>
    FLOOR
  end

  def build_page(game, chapters, pokemon_hash, item_hash, _map_hash)
    return nil unless JaNames.enabled? && data

    labels = data['stickers'].to_h { |s| [s, "デパートステッカー「#{species_name(s['species'], pokemon_hash)}」"] }
    found = MachineIndex.locations(chapters, game, labels.values)
    places = labels.transform_values { |label| (found[label] || {}).values }

    # 本文に出てくる順 (= 集める順) に並べる。本文に無いものは後ろへ。
    order = chapters.each_with_index.to_h { |c, i| [c[:title], i] }
    stickers = data['stickers'].sort_by.with_index do |s, i|
      [places[s].map { |p| order[p[:chapter]] || 999 }.min || 999, i]
    end

    stock = floor_items
    floors = data['floors']
    total = stickers.size
    top = split_floor(floors.last['label_ja'])[0]

    body = <<~PAGE
      ---
      title: デパートステッカー
      permalink: /#{game}/stickers/
      description: "ポケモンリボーンのデパートステッカー#{total}枚の集め方と、デパート各階の品ぞろえ。"
      ---

      <p id="title-text">デパートステッカー</p>

      <p class="ref-back"><a href="/#{game}/">#{JaNames.ui('Back to contents')}</a></p>

      オブシディア区のデパートでは、メンバーズカードに貼ったステッカーの枚数で行ける階が決まります。1階は最初から入れて、カードに付いてくる1枚で2階へ、あとは1枚ごとに1階ずつ上へ行けるようになります。全#{total}枚で#{esc(top)}まで行けます。

      ## ステッカーの集め方 {#stickers}

      <div class="stk-list">
      #{stickers.each_with_index.map { |s, i| sticker_html(s, i + 1, places[s], pokemon_hash) }.join}
      </div>

      ## 各階の品ぞろえ {#floors}

      <div class="stk-floors">
      #{floors.each_with_index.map { |f, i|
        items = i == floors.size - 1 ? penthouse_items(item_hash) : stock[i + 1]
        floor_html(f, i, items)
      }.join}
      </div>

    PAGE
    Spoiler.apply(body)
  end
end
