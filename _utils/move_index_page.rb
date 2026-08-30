# frozen_string_literal: true

require_relative 'ja_names'
require_relative 'mon_data'
require_relative 'move_index'
require_relative 'sort_header'

# わざの一覧ページ。個別ページ (/reborn/move/<英名>/) の入口。
#
# 覚え手のいるわざだけを並べる。実測で691本。名前・タイプ・分類で絞れる。
# 「覚えるポケモン」の数を列に持たせてあるので、押す前に行った先の量が分かる。
module MoveIndexPage
  module_function

  CATEGORIES = %i[physical special status].freeze

  def esc(text)
    text.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;').gsub('"', '&quot;')
  end

  def ui(text)
    esc(JaNames.ui(text))
  end

  # 5万を「50043」と書くと桁が読めない。
  def comma(number)
    number.to_s.reverse.scan(/\d{1,3}/).join(',').reverse
  end

  def type_badge(sym)
    t = sym.to_s.downcase
    label = sym == :QMARKS ? '???' : JaNames.tr('types', sym.to_s.capitalize)
    cls = sym == :QMARKS ? 'qmarks' : t
    %(<span class="type-badge type-#{cls}">#{esc(label)}</span>)
  end

  # 並べ替えに使う値。表に出るのは「—」や「必中」なので、字を読んで並べても
  # 数の大小にならない。命中0はゲームでは「必ず当たる」なので、100 の上に置く。
  def sort_keys(move, count)
    { power: move[:basedamage].to_i,
      acc: move[:accuracy].to_i.zero? ? 101 : move[:accuracy].to_i,
      pp: move[:maxpp].to_i,
      count: count }
  end

  def row_html(game, move_sym, move, count)
    power = move[:basedamage].to_i.positive? ? move[:basedamage].to_s : '—'
    accuracy = move[:accuracy].to_i.zero? ? ui('Perfect') : "#{move[:accuracy]}%"
    en = move[:name_en] || move_sym.to_s.capitalize
    keys = sort_keys(move, count).map { |name, value| %(data-#{name}="#{value}") }.join(' ')

    %(<tr data-name="#{esc(move[:name])}" data-en="#{esc(en)}" ) +
      %(data-types="#{move[:type].to_s.downcase}" data-cat="#{move[:category]}" #{keys}>) +
      %(<td class="mvi-type">#{type_badge(move[:type])}</td>) +
      %(<td class="mvi-name"><a href="/#{game}/move/#{move_sym.to_s.downcase}/">#{esc(move[:name])}</a>) +
      %(<span class="mvi-en">#{esc(en)}</span></td>) +
      %(<td class="mvi-cat">#{esc(MonData.category_label(move[:category]))}</td>) +
      %(<td class="md-num">#{power}</td>) +
      %(<td class="md-num">#{accuracy}</td>) +
      %(<td class="md-num">#{esc(move[:maxpp] || '—')}</td>) +
      %(<td class="mvi-count"><span>#{count}</span></td></tr>)
  end

  # 見出しの行。数の4列は押して並べ替えられるようにする (SortHeader)。
  #
  # 既定は覚える数の降順で組んであるので、その列だけ最初から印を付けておく。
  def head_html(ja)
    cells = [[nil, ui('Type')], [nil, ui('Moves')], [nil, ui('Category')],
             ['power', ui('Power')], ['acc', ui('Accuracy')], ['pp', ui('PP')],
             ['count', ja ? '覚える数' : 'Learners']]

    cells.map { |key, label|
      next %(<th>#{label}</th>) unless key

      SortHeader.th(key, label, on: key == 'count')
    }.join
  end

  def filter_html(type_counts, cat_counts)
    ja = JaNames.enabled?
    type_chips = MonData::TYPE_ORDER.filter_map { |type|
      count = type_counts[type]
      next unless count&.positive?

      %(<button type="button" class="ref-chip type-badge type-#{type}" data-value="#{type}" ) +
        %(aria-pressed="false">#{esc(JaNames.tr('types', type.capitalize))}<span>#{count}</span></button>)
    }.join
    cat_chips = CATEGORIES.filter_map { |cat|
      count = cat_counts[cat]
      next unless count&.positive?

      %(<button type="button" class="ref-chip mvi-chip is-#{cat}" data-value="#{cat}" ) +
        %(aria-pressed="false">#{esc(MonData.category_label(cat))}<span>#{count}</span></button>)
    }.join

    <<~BAR
      <div class="ref-filter mvi-filter" hidden>
        <div class="ref-filter-line">
          <input type="search" id="mvi-q" class="ref-search" autocomplete="off"
                 placeholder="#{ja ? 'わざの名前で絞る（かな・英語名も可）' : 'Filter by move name'}">
          <span class="ref-count" role="status" aria-live="polite"></span>
        </div>
        <div class="ref-filter-line ref-chips" data-group="types">
          <span class="ref-chip-label">#{ui('Type')}</span>#{type_chips}
        </div>
        <div class="ref-filter-line ref-chips" data-group="cats">
          <span class="ref-chip-label">#{ui('Category')}</span>#{cat_chips}
          <button type="button" class="ref-reset">#{ui('Clear')}</button>
        </div>
      </div>
    BAR
  end

  def build_page(game, move_hash)
    rows = MoveIndex.moves.filter_map { |sym|
      move = move_hash[sym]
      next unless move

      [sym, move, MoveIndex.count(sym)]
    }
    return nil if rows.empty?

    # 並びはタイプ順のなかで五十音…にはしない。ゲームのデータ順 (ID順) は
    # 読者に意味が無いので、覚え手の多い順にする。「どのポケモンでも持てる
    # わざ」から先に見えるほうが、手持ちを組むときの当たりが早い。
    rows = rows.sort_by { |sym, move, count| [-count, move[:name].to_s, sym.to_s] }

    type_counts = Hash.new(0)
    cat_counts = Hash.new(0)
    rows.each do |_sym, move, _count|
      type_counts[move[:type].to_s.downcase] += 1
      cat_counts[move[:category]] += 1
    end

    ja = JaNames.enabled?
    title = ja ? 'わざから探す' : 'Move Index'
    total_pairs = rows.sum { |_, _, count| count }

    lead =
      if ja
        ["覚えられるポケモンが1種以上いるわざ#{rows.length}本の一覧です。" \
         "わざの名前を押すと、そのわざを覚えられるポケモンが図鑑番号順に並びます。" \
         "レベル・わざマシン・教え技・タマゴ・思い出しのどれで覚えるかも一緒に出ます。",
         "並びは覚えられるポケモンの多い順。のべ#{comma(total_pairs)}組をゲームのデータから起こしています。"]
      else
        ["#{rows.length} moves that at least one Pokemon can learn. " \
         "Open a move to see every Pokemon that learns it, by any method.",
         "Sorted by how many Pokemon can learn it. #{comma(total_pairs)} pairs in total."]
      end

    heads = head_html(ja)

    <<~PAGE
      ---
      layout: default
      title: #{title}
      permalink: /#{game}/move/
      description: "ポケモンリボーンのわざ一覧。指定のわざを覚えられるポケモンを、レベル・わざマシン・教え技を問わず引けます。"
      ---

      <p id="title-text">#{title}</p>

      <p class="ref-back"><a href="/#{game}/">#{ui('Back to contents')}</a> · <a href="/#{game}/mon/">#{ui('Pokemon list')}</a></p>

      <p>#{esc(lead[0])}</p>

      <p>#{esc(lead[1])}</p>

      #{filter_html(type_counts, cat_counts)}

      <div class="md-scroll"><table class="mvi-table">
      <thead><tr>#{heads}</tr></thead>
      <tbody>#{rows.map { |sym, move, count| row_html(game, sym, move, count) }.join}</tbody>
      </table></div>
    PAGE
  end
end
