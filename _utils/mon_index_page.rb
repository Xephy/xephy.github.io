# frozen_string_literal: true

require_relative 'ja_names'
require_relative 'mon_data'
require_relative 'encounter_index'

# ポケモン個別ページの入口となる一覧。
#
# 個別ページは本文のアイコンから直に飛べるが、「あのポケモンの頁を開きたい」
# だけのときに通る場所が要る。図鑑番号順に並べ、名前とタイプで絞れるようにする。
#
# 名前はひらがなでも英語名でも引ける (出現場所ページと同じ扱い)。
module MonIndexPage
  module_function

  def esc(text)
    text.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;').gsub('"', '&quot;')
  end

  def ui(text)
    esc(JaNames.ui(text))
  end

  def type_badge(sym)
    t = sym.to_s.downcase
    label = sym == :QMARKS ? '???' : JaNames.tr('types', sym.to_s.capitalize)
    %(<span class="type-badge type-#{t}">#{esc(label)}</span>)
  end

  def card(game, species, forms)
    data = MonData.base_data(forms)
    types = [data[:Type1], data[:Type2]].compact
    icon = mon_icon_src(species, 0)
    wild = EncounterIndex.has_species?(species.to_s) ? 1 : 0

    %(<a class="mi-card" href="/#{game}/mon/#{MonData.slug(species)}/" ) +
      %(data-name="#{esc(data[:name])}" data-en="#{MonData.slug(species)}" ) +
      %(data-types="#{types.map { |t| t.to_s.downcase }.join(' ')}" data-wild="#{wild}">) +
      (icon ? %(<img src="#{icon}" alt="" class="mon-icon mi-icon" width="32" height="32" loading="lazy">) : '') +
      %(<span class="mi-body"><span class="mi-name">#{esc(data[:name])}</span>) +
      %(<span class="mi-meta"><span class="mi-dex">No.#{format('%03d', data[:dexnum].to_i)}</span>) +
      %(<span class="mi-types">#{types.map { |t| type_badge(t) }.join}</span></span></span></a>)
  end

  def filter_bar(counts, wild_count)
    chips = MonData::TYPE_ORDER.filter_map { |type|
      count = counts[type]
      next unless count&.positive?

      label = JaNames.tr('types', type.capitalize)
      %(<button type="button" class="ref-chip type-badge type-#{type}" data-value="#{type}">) +
        %(#{esc(label)}<span>#{count}</span></button>)
    }.join

    <<~BAR
      <div class="ref-filter mi-filter" hidden>
        <div class="ref-filter-line">
          <input type="search" id="mi-q" class="ref-search" autocomplete="off"
                 placeholder="#{ui('Filter by name')}">
          <span class="ref-count" role="status" aria-live="polite"></span>
        </div>
        <div class="ref-filter-line ref-chips" data-group="types">
          <span class="ref-chip-label">#{ui('Type')}</span>#{chips}
        </div>
        <div class="ref-filter-line">
          <label class="ref-toggle"><input type="checkbox" id="mi-wild">
            #{ui('Wild only')}<span>#{wild_count}</span></label>
          <button type="button" class="ref-reset">#{ui('Clear')}</button>
        </div>
      </div>
    BAR
  end

  # 横断して探すときの行き先。個別ページは1匹ぶんしか答えられないので、
  # 「今どこまでで何が捕れるか」「交換が要るのは誰か」は資料ページへ送る。
  def cross_links(game)
    if JaNames.enabled?
      %(<p class="md-note">場所や条件から横断して探すときは、) +
        %(<a href="/#{game}/pokemon/">ポケモンの出現場所</a>（章ごと・出現方法で絞れます）と) +
        %(<a href="/#{game}/evolutions/">進化条件の一覧</a>（方法で絞れます）があります。</p>)
    else
      %(<p class="md-note">To search across species, see ) +
        %(<a href="/#{game}/pokemon/">Wild Encounters</a> (by chapter or method) and ) +
        %(<a href="/#{game}/evolutions/">Evolution Methods</a> (by method).</p>)
    end
  end

  def build_page(game, pokemon_hash)
    return nil if pokemon_hash.nil? || pokemon_hash.empty?

    entries = pokemon_hash.filter_map { |species, forms|
      data = MonData.base_data(forms)
      next unless data && data[:name]

      [data[:dexnum].to_i, species, forms]
    }.sort_by { |dexnum, species, _| [dexnum, species.to_s] }

    counts = Hash.new(0)
    wild_count = 0
    entries.each do |_, species, forms|
      data = MonData.base_data(forms)
      [data[:Type1], data[:Type2]].compact.each { |t| counts[t.to_s.downcase] += 1 }
      wild_count += 1 if EncounterIndex.has_species?(species.to_s)
    end

    cards = entries.map { |_, species, forms| card(game, species, forms) }.join("\n")
    title = JaNames.enabled? ? 'ポケモン図鑑' : 'Pokédex'

    lead =
      if JaNames.enabled?
        "ゲームに出てくる#{entries.length}種の一覧です。名前を押すと、覚えるわざ・出現場所・" \
        "進化条件をまとめた頁へ移ります。#{wild_count}種は野生で出会えます。"
      else
        "All #{entries.length} species in the game. Open one for its moves, wild locations " \
        "and evolutions. #{wild_count} of them appear in the wild."
      end

    # 英語名の例は意図して英語で出す。md-en は「訳し忘れではない」印で、
    # bin/check-rendered はこの印の中を数えない。
    note =
      if JaNames.enabled?
        '名前はひらがな（にゃーす）でも英語名（<span class="md-en">meowth</span>）でも' \
        '引けます。/ キーで入力欄に移れます。'
      else
        'Search by name or by its English name. Press / to jump to the search box.'
      end

    <<~PAGE
      ---
      layout: default
      title: "#{title}"
      permalink: /#{game}/mon/
      ---

      <p id="title-text">#{esc(title)}</p>

      <p class="ref-back"><a href="/#{game}/">#{ui('Back to contents')}</a></p>

      <p>#{esc(lead)}</p>

      <p class="md-note">#{note}</p>

      #{cross_links(game)}

      #{filter_bar(counts, wild_count)}

      <div class="mi-grid">
      #{cards}
      </div>
    PAGE
  end
end
