# frozen_string_literal: true

require_relative 'ja_names'
require_relative 'common'
require_relative 'mon_data'
require_relative 'sort_header'

# 種族値ランキング (/reborn/stats/)。
#
# ポケモン個別ページは1種ぶんの数字しか答えられない。「とくぼうの高い順に
# 見たい」という引き方をするには、全種を1枚に並べて、列で並べ替えられる
# 必要がある。フィールドの都合で特定の能力が高いポケモンを探す場面
# (14章のテラ戦など) から来る。
#
# メガ・ゲンシ・特殊フォルムは種族値そのものが変わるので別の行にする。
# 図鑑に出ない姿 (PULSE など) は入手できないので外す。
module StatIndexPage
  module_function

  # 行に持たせる並べ替えの鍵。MonData::STATS と同じ並び。
  STAT_KEYS = %w[hp atk def spa spd spe].freeze

  def esc(text)
    text.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;').gsub('"', '&quot;')
  end

  def ui(text)
    esc(JaNames.ui(text))
  end

  def type_badge(sym)
    t = sym.to_s.downcase
    label = sym == :QMARKS ? '???' : JaNames.tr('types', sym.to_s.capitalize)
    cls = sym == :QMARKS ? 'qmarks' : t
    %(<span class="type-badge type-#{cls}">#{esc(label)}</span>)
  end

  # 1行ぶんの材料。種族ではなく「姿」を単位にする。
  #
  # 同じ数値の姿はまとめる。アンノーンの26文字やビビヨンの模様は見た目が
  # 違うだけなので、まとめないと同じ行が26本並ぶ。
  def collect(pokemon_hash)
    rows = pokemon_hash.flat_map { |species, forms|
      form_keys = MonData.form_keys(forms)
      base = forms[form_keys.first]
      next [] unless base && base[:dexnum].to_i.positive?

      seen = {}
      form_keys.filter_map { |form_key|
        next if forms[form_key][:ExcludeDex]

        stats = MonData.attr_of(forms, form_key, :BaseStats) || []
        next if stats.length != 6 || seen[stats]

        seen[stats] = true
        { species: species, form_key: form_key, form_index: form_keys.index(form_key),
          alt: form_key != form_keys.first, name: base[:name], dexnum: base[:dexnum].to_i,
          types: [MonData.attr_of(forms, form_key, :Type1),
                  MonData.attr_of(forms, form_key, :Type2)].compact,
          stats: stats }
      }
    }

    # 既定は合計の高い順。同じ合計は図鑑番号で並べ、その中では基本形を先に
    # 置く。JavaScript 側はこの並びを同値のときの順として使い回すので、
    # 「こうげきが同じなら合計の高いほうが上」が全部の列で保たれる。
    rows.sort_by { |row| [-row[:stats].sum, row[:dexnum], row[:form_index]] }
  end

  def row_html(game, row)
    total = row[:stats].sum
    avg = (total / 6.0).round(1)
    form = row[:alt] ? MonData.form_label(row[:form_key]) : nil
    icon = mon_icon_src(row[:species], row[:form_index])
    keys = STAT_KEYS.each_with_index.map { |key, i| %(data-#{key}="#{row[:stats][i]}") }.join(' ')

    %(<tr data-name="#{esc(row[:name])}" data-en="#{MonData.slug(row[:species])}" ) +
      %(data-form="#{esc(form)}" data-alt="#{row[:alt] ? 'alt' : 'base'}" ) +
      %(data-types="#{row[:types].map { |t| t.to_s.downcase }.join(' ')}" ) +
      %(#{keys} data-total="#{total}" data-avg="#{avg}">) +
      %(<td class="bst-type">#{row[:types].map { |t| type_badge(t) }.join}</td>) +
      %(<td class="bst-name"><a href="/#{game}/mon/#{MonData.slug(row[:species])}/">) +
      (icon ? %(<img src="#{icon}" alt="" class="mon-icon bst-icon" width="32" height="32" loading="lazy">) : '') +
      %(<span>#{esc(row[:name])}</span></a>) +
      (form ? %(<span class="bst-form">#{esc(form)}</span>) : '') + '</td>' +
      row[:stats].map { |value| %(<td class="md-num">#{value}</td>) }.join +
      %(<td class="md-num bst-total">#{total}</td>) +
      %(<td class="md-num bst-avg">#{format('%.1f', avg)}</td></tr>)
  end

  # 見出しの行。数の8列すべてで並べ替えられる。
  # 既定は合計の降順で組んであるので、その列だけ最初から印を付けておく。
  def head_html(ja)
    cells = [[nil, ja ? 'タイプ' : 'Type'], [nil, ja ? 'ポケモン' : 'Pokemon']] +
            STAT_KEYS.each_with_index.map { |key, i| [key, esc(MonData.stat_label(i))] } +
            [['total', ja ? '合計' : 'Total'], ['avg', ja ? '平均' : 'Avg']]

    cells.map { |key, label|
      next %(<th>#{label}</th>) unless key

      SortHeader.th(key, label, on: key == 'total')
    }.join
  end

  def filter_html(rows)
    ja = JaNames.enabled?
    type_counts = Hash.new(0)
    rows.each { |row| row[:types].each { |t| type_counts[t.to_s.downcase] += 1 } }
    alt_count = rows.count { |row| row[:alt] }

    type_chips = MonData::TYPE_ORDER.filter_map { |type|
      count = type_counts[type]
      next unless count&.positive?

      %(<button type="button" class="ref-chip type-badge type-#{type}" data-value="#{type}" ) +
        %(aria-pressed="false">#{esc(JaNames.tr('types', type.capitalize))}<span>#{count}</span></button>)
    }.join

    form_chips = [['base', ja ? '基本の姿' : 'Base form', rows.length - alt_count],
                  ['alt', ja ? 'ほかの姿' : 'Other forms', alt_count]].map { |value, label, count|
      %(<button type="button" class="ref-chip bst-chip" data-value="#{value}" ) +
        %(aria-pressed="false">#{esc(label)}<span>#{count}</span></button>)
    }.join

    <<~BAR
      <div class="ref-filter bst-filter" hidden>
        <div class="ref-filter-line">
          <input type="search" id="bst-q" class="ref-search" autocomplete="off"
                 placeholder="#{ja ? 'ポケモンの名前で絞る（かな・英語名も可）' : 'Filter by name'}">
          <span class="ref-count" role="status" aria-live="polite"></span>
        </div>
        <div class="ref-filter-line ref-chips" data-group="types">
          <span class="ref-chip-label">#{ja ? 'タイプ' : 'Type'}</span>#{type_chips}
        </div>
        <div class="ref-filter-line ref-chips" data-group="forms">
          <span class="ref-chip-label">#{ja ? 'すがた' : 'Form'}</span>#{form_chips}
          <button type="button" class="ref-reset">#{ui('Clear')}</button>
        </div>
      </div>
    BAR
  end

  def build_page(game, pokemon_hash)
    return nil if pokemon_hash.nil? || pokemon_hash.empty?

    rows = collect(pokemon_hash)
    return nil if rows.empty?

    ja = JaNames.enabled?
    title = ja ? '種族値ランキング' : 'Base Stat Ranking'
    species_count = rows.count { |row| !row[:alt] }
    alt_count = rows.length - species_count

    lead =
      if ja
        ["#{species_count}種＋メガ・ゲンシなど別の姿#{alt_count}件、合わせて#{rows.length}件の種族値です。" \
         '見出しを押すと、その能力の高い順に並び替わります。もう一度押すと低い順になります。',
         '「このフィールドではとくぼうの高いポケモンが要る」のように、能力から手持ちを' \
         '探すための表です。名前を押すと、覚えるわざや出現場所を載せた個別ページへ移ります。']
      else
        ["Base stats for #{species_count} species plus #{alt_count} alternate forms " \
         "(#{rows.length} rows). Click a heading to sort by that stat, click again to reverse.",
         'Use it to pick a party member by its stats. Open a name for its moves and locations.']
      end

    note =
      if ja
        '姿ちがいは種族値が変わるものだけを別の行にしています。図鑑に出ない姿（PULSE など）は' \
        '入手できないので載せていません。平均は合計を6で割った値なので、並ぶ順は合計と同じです。'
      else
        'Alternate forms appear only when their stats differ. Forms hidden from the Pokedex ' \
        '(PULSE and the like) are left out. The average is the total divided by six, so it sorts alike.'
      end

    <<~PAGE
      ---
      layout: default
      title: "#{title}"
      permalink: /#{game}/stats/
      description: "ポケモンリボーンの種族値一覧。HP・攻撃・防御・特攻・特防・素早さ・合計・平均のどれでも並べ替えられます。タイプでの絞り込みにも対応。"
      ---

      <p id="title-text">#{esc(title)}</p>

      <p class="ref-back"><a href="/#{game}/">#{ui('Back to contents')}</a> · <a href="/#{game}/mon/">#{ui('Pokemon list')}</a></p>

      <p>#{esc(lead[0])}</p>

      <p>#{esc(lead[1])}</p>

      <p class="md-note">#{esc(note)}</p>

      #{filter_html(rows)}

      <div class="md-scroll"><table class="bst-table">
      <thead><tr>#{head_html(ja)}</tr></thead>
      <tbody>#{rows.map { |row| row_html(game, row) }.join}</tbody>
      </table></div>
    PAGE
  end
end
