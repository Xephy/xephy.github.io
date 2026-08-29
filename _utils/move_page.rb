# frozen_string_literal: true

require_relative 'ja_names'
require_relative 'mon_data'
require_relative 'move_facts'
require_relative 'move_index'
require_relative 'move_index_page'

# わざ1本につき1ページ。
#
# 図鑑ができて「このポケモンは何を覚えるか」は引けるようになったが、逆が
# 引けない。手持ちを組むときの引き方はむしろ逆で、「こおりのわざを持たせたい。
# 誰が覚えるのか」から入る。図鑑と対になる向きをここで埋める。
#
# 誰も覚えないわざ (イベント専用など) はページを作らない。実測で
# データ上862本のうち、覚え手がいるのは691本。
module MovePage
  module_function

  # 覚え方の札。図鑑の個別ページのタブと同じ言い方にそろえる。
  WAY_LABEL = { level: 'Level', machine: 'TMs', tutor: 'Tutor moves',
                egg: 'Egg moves', relearner: 'Relearner moves', shadow: 'Shadow Moves' }.freeze

  def esc(text)
    text.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;').gsub('"', '&quot;')
  end

  def ui(text)
    esc(JaNames.ui(text))
  end

  def slug(move_sym)
    move_sym.to_s.downcase
  end

  def href(game, move_sym)
    "/#{game}/move/#{slug(move_sym)}/"
  end

  def type_badge(sym, extra = nil)
    t = sym.to_s.downcase
    label = sym == :QMARKS ? '???' : JaNames.tr('types', sym.to_s.capitalize)
    cls = sym == :QMARKS ? 'qmarks' : t
    %(<span class="type-badge type-#{cls}#{extra ? " #{extra}" : ''}">#{esc(label)}</span>)
  end

  # --- 覚え方の札 -----------------------------------------------------------

  # レベルだけは値を出す。「Lv.35 で覚える」と「マシンで覚える」では、
  # 手持ちに入れるかどうかの判断がまるで違う。
  def way_chip(way, level)
    text = if way == :level
             level.to_i <= 1 ? JaNames.ui('From the start') : "#{JaNames.ui('Lv.')}#{level}"
           else
             JaNames.ui(WAY_LABEL[way])
           end
    %(<span class="mv-way is-#{way}">#{esc(text)}</span>)
  end

  # --- ポケモンの札 ---------------------------------------------------------

  # 姿によって覚えるかどうかが変わる。アローラのサンドはれいとうパンチを
  # 覚えるが、カントーのサンドは覚えない。覚えるほうの姿でアイコン・タイプ・
  # 名前をそろえないと、じめんタイプの札の下にこおりの姿の絵が出てしまう。
  #
  # いちばん若い姿を代表にする。基本形が覚えるならそれが選ばれ、札は今までと
  # 同じ見た目になる。基本形が覚えないときだけ、姿の名前を添える。
  # 代表にする姿。いちばん若いもの = 基本形が覚えるなら基本形。
  def card_form(forms, slot)
    keys = MonData.form_keys(forms)
    index = slot[:forms].min || 0
    [index, keys[index] || keys.first]
  end

  def card_types(forms, slot)
    _index, form_key = card_form(forms, slot)
    [MonData.attr_of(forms, form_key, :Type1),
     MonData.attr_of(forms, form_key, :Type2)].compact
  end

  def card(game, species, forms, slot)
    form_index, form_key = card_form(forms, slot)
    data = MonData.base_data(forms)
    types = card_types(forms, slot)
    icon = mon_icon_src(species, form_index)
    ways = MoveIndex::WAYS.select { |w| slot[:ways].key?(w) }
    form_note = form_index.positive? ? MonData.form_label(form_key) : nil

    %(<a class="mi-card mv-card" href="/#{game}/mon/#{MonData.slug(species)}/" ) +
      %(data-name="#{esc(data[:name])}#{form_note ? " #{esc(form_note)}" : ''}" data-en="#{MonData.slug(species)}" ) +
      %(data-types="#{types.map { |t| t.to_s.downcase }.join(' ')}" ) +
      %(data-ways="#{ways.join(' ')}">) +
      (icon ? %(<img src="#{icon}" alt="" class="mon-icon mi-icon" width="32" height="32" loading="lazy">) : '') +
      %(<span class="mi-body"><span class="mi-name">#{esc(data[:name])}</span>) +
      # 姿の名前は名前と同じ行に置かない。「サンドパン アローラのすがた」で
      # 札の幅を越え、末尾が「…」に切られていた。
      (form_note ? %(<span class="mv-form">#{esc(form_note)}</span>) : '') +
      %(<span class="mi-meta"><span class="mi-dex">No.#{format('%03d', data[:dexnum].to_i)}</span>) +
      %(<span class="mi-types">#{types.map { |t| type_badge(t) }.join}</span></span>) +
      %(<span class="mv-ways">#{ways.map { |w| way_chip(w, slot[:ways][:level]) }.join}</span>) +
      %(</span></a>)
  end

  # --- 絞り込み -------------------------------------------------------------

  def filter_html(type_counts, way_counts, total)
    ja = JaNames.enabled?
    # 札が1種類しか無いなら、押しても件数が変わらない。出さない。
    type_chips = MonData::TYPE_ORDER.filter_map { |type|
      count = type_counts[type]
      next unless count&.positive?

      %(<button type="button" class="ref-chip type-badge type-#{type}" data-value="#{type}" ) +
        %(aria-pressed="false">#{esc(JaNames.tr('types', type.capitalize))}<span>#{count}</span></button>)
    }
    way_chips = MoveIndex::WAYS.filter_map { |way|
      count = way_counts[way]
      next unless count&.positive?

      %(<button type="button" class="ref-chip mv-way is-#{way}" data-value="#{way}" ) +
        %(aria-pressed="false">#{ui(WAY_LABEL[way])}<span>#{count}</span></button>)
    }

    lines = []
    lines << <<~LINE
      <div class="ref-filter-line">
        <input type="search" id="ml-q" class="ref-search" autocomplete="off"
               placeholder="#{ja ? 'ポケモンの名前で絞る（かな・英語名も可）' : 'Filter by Pokemon name'}">
        <span class="ref-count" role="status" aria-live="polite"></span>
      </div>
    LINE
    if type_chips.size > 1
      lines << %(<div class="ref-filter-line ref-chips" data-group="types">) +
               %(<span class="ref-chip-label">#{ui('Type')}</span>#{type_chips.join}</div>)
    end
    if way_chips.size > 1
      lines << %(<div class="ref-filter-line ref-chips" data-group="ways">) +
               %(<span class="ref-chip-label">#{ja ? '覚え方' : 'How'}</span>#{way_chips.join}</div>)
    end
    lines << %(<div class="ref-filter-line"><button type="button" class="ref-reset">#{ui('Clear')}</button></div>)

    return '' if total < 2

    %(<div class="ref-filter ml-filter" hidden>#{lines.join}</div>)
  end

  # --- 覚え方の出どころ -----------------------------------------------------

  # わざマシンと教え人は「どこで手に入るか」まで答えられる。レベルやタマゴと
  # 違って場所が決まっているので、ここだけは本文へ送る。
  def sources_html(game, move_sym, move, ctx)
    ja = JaNames.enabled?
    rows = []

    machine = ctx[:machines].find { |m| m[:move].equal?(move) || m[:move] == move }
    if machine
      anchor = "#{machine[:kind] == 1 ? 'hm' : 'tm'}-#{machine[:number]}"
      places = machine[:places].map { |s|
        %(<a href="#{s[:href]}">#{esc(s[:text])}</a>)
      }
      where = places.empty? ? %(<span class="md-empty">#{ja ? '本文に記載なし' : 'Not in the walkthrough'}</span>) : places.join('・')
      rows << [%(<a href="/#{game}/tms/##{anchor}">#{esc(machine[:label])}</a>), where]
    end

    (ctx[:tutors][move[:name]] || []).each do |tutor|
      where = %(<a href="#{tutor.dig(:context, :href)}">#{esc(tutor[:tutor])}</a>) +
              %(<span class="md-price">#{esc(tutor[:price])}</span>)
      rows << [ui('Tutor moves'), where]
    end

    return '' if rows.empty?

    body = rows.map { |lead, where|
      %(<div class="mv-source"><span class="mv-source-lead">#{lead}</span>) +
        %(<span class="mv-source-where">#{where}</span></div>)
    }.join
    %(<section class="md-sec"><h2>#{ja ? '手に入る場所' : 'Where to get it'}</h2>) +
      %(<div class="md-card">#{body}</div></section>)
  end

  # --- ページ ---------------------------------------------------------------

  def hero(move, move_sym)
    power = move[:basedamage].to_i.positive? ? move[:basedamage].to_s : '—'
    accuracy = move[:accuracy].to_i.zero? ? ui('Perfect') : "#{move[:accuracy]}%"
    facts = [[ui('Category'), esc(MonData.category_label(move[:category]))],
             [ui('Power'), "<strong>#{power}</strong>"],
             [ui('Accuracy'), accuracy],
             [ui('PP'), esc(move[:maxpp] || '—')]]

    <<~HTML
      <div class="mv-hero">
        <div class="mv-hero-id">
          #{type_badge(move[:type])}
          <p class="mv-hero-name">#{esc(move[:name])}#{JaNames.enabled? ? %(<span class="md-en">#{esc(move[:name_en] || move_sym.to_s.capitalize)}</span>) : ''}</p>
        </div>
        <dl class="md-facts">
          #{facts.map { |label, value| %(<div class="md-fact"><dt>#{label}</dt><dd>#{value}</dd></div>) }.join}
        </dl>
      </div>
    HTML
  end

  # 説明文と、そのあとに続く実測値 (急所率・追加効果の確率・能力変化の段階)。
  # 図鑑では title 属性に畳んでいるが、ここは主役なので開いて出す。
  def description(move, scripts_dir, move_sym)
    lines = MoveFacts.lines(move, scripts_dir, move_sym)
    %(<p class="mv-desc">#{esc(move[:desc])}</p>) +
      (lines.empty? ? '' : %(<ul class="mv-facts">#{lines.map { |l| "<li>#{esc(l)}</li>" }.join}</ul>))
  end

  def build_page(game, scripts_dir, move_sym, move, hashes, ctx, dex_index)
    pokemon_hash = hashes[:pokemon]
    learners = MoveIndex.learners(move_sym, dex_index)

    type_counts = Hash.new(0)
    way_counts = Hash.new(0)
    cards = learners.filter_map { |species|
      forms = pokemon_hash[species]
      next unless forms

      slot = MoveIndex.slot(move_sym, species)
      # 札の数は札そのものと同じ姿から数える。基本形とちがう姿で覚える
      # ものがあるので、base_data から数えると絞り込みの件数がずれる。
      card_types(forms, slot).each { |t| type_counts[t.to_s.downcase] += 1 }
      slot[:ways].each_key { |w| way_counts[w] += 1 }
      card(game, species, forms, slot)
    }

    ja = JaNames.enabled?
    lead =
      if ja
        "『ポケモンリボーン』で#{move[:name]}を覚えられるポケモンは#{cards.size}種です。" \
        'レベル・わざマシン・教え技・タマゴ・思い出しのどれかで覚えられるものを、' \
        '図鑑番号順にすべて並べています。'
      else
        "#{cards.size} Pokemon can learn #{move[:name]} in Pokemon Reborn, by any method."
      end

    <<~PAGE
      ---
      layout: default
      title: "#{move[:name]}"
      permalink: #{href(game, move_sym)}
      description: "『ポケモンリボーン』の#{move[:name]}。覚えられるポケモン#{cards.size}種と、威力・命中・追加効果をまとめています。"
      ---

      <p id="title-text">#{esc(move[:name])}</p>

      <p class="ref-back"><a href="/#{game}/">#{ui('Back to contents')}</a> · <a href="/#{game}/move/">#{ja ? 'わざ一覧' : 'Move list'}</a></p>

      #{hero(move, move_sym)}

      #{description(move, scripts_dir, move_sym)}

      #{sources_html(game, move_sym, move, ctx)}

      <section class="md-sec">
      <h2>#{ja ? '覚えるポケモン' : 'Pokemon that learn it'} <span class="md-count">#{cards.size}</span></h2>

      <p class="mv-lead">#{esc(lead)}</p>

      #{filter_html(type_counts, way_counts, cards.size)}

      <div class="mi-grid ml-grid">#{cards.join}</div>
      </section>
    PAGE
  end

  # 覚え手のいるわざぶんだけページを作る。索引ページも同じ場所に置く。
  def build_pages(game, scripts_dir, hashes, ctx)
    move_hash = hashes[:move]
    pokemon_hash = hashes[:pokemon]
    return {} if move_hash.nil? || pokemon_hash.nil? || MoveIndex.entries.empty?

    dex_index = pokemon_hash.each_key.with_index.to_h { |species, i|
      data = MonData.base_data(pokemon_hash[species])
      [species, [data && data[:dexnum].to_i, i]]
    }
    # 図鑑番号が同じもの (姿違い) が来ても並びが揺れないよう、番号のあとに
    # データの並び順を添える。
    ordering = dex_index.transform_values { |num, i| (num.to_i.positive? ? num.to_i : 9000) * 10_000 + i }

    pages = {}
    MoveIndex.moves.each do |move_sym|
      move = move_hash[move_sym]
      next unless move

      pages[slug(move_sym)] = build_page(game, scripts_dir, move_sym, move, hashes, ctx, ordering)
    end

    index = MoveIndexPage.build_page(game, move_hash)
    pages['index'] = index if index
    pages
  end
end
