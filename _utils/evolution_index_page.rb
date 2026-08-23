# frozen_string_literal: true

require_relative 'ja_names'
require_relative 'common'
require_relative 'evolution_index'
require_relative 'encounter_index'

# 進化条件の一覧ページ。
module EvolutionIndexPage
  module_function

  GROUP_LABELS = {
    'level' => 'レベル', 'item' => 'どうぐ', 'trade' => '通信交換',
    'happiness' => 'なつき度', 'location' => '場所', 'other' => 'その他'
  }.freeze

  GROUP_LABELS_EN = {
    'level' => 'Level', 'item' => 'Item', 'trade' => 'Trade',
    'happiness' => 'Happiness', 'location' => 'Location', 'other' => 'Other'
  }.freeze

  # 進化の方法の呼び名。ポケモン個別ページからも同じ言葉で参照する。
  def group_label(group)
    (JaNames.enabled? ? GROUP_LABELS : GROUP_LABELS_EN)[group] || group.to_s
  end

  def esc(text)
    text.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;').gsub('"', '&quot;')
  end

  def mon_cell(sym, pokemon_hash, form_index = 0)
    name = EvolutionIndex.species_name(sym, pokemon_hash)
    icon = mon_icon_src(sym, form_index)
    img = icon ? %(<img src="#{icon}" alt="" class="mon-icon ev-icon" loading="lazy" width="32" height="32">) : ''
    # 飛び先はポケモン個別ページ。以前は出現場所ページを絞った状態へ送って
    # いたが、野生に出ない種族は行き先が無かった。
    inner = %(#{img}<span class="ev-name">#{esc(name)}</span>)
    %(<a class="mon-link" href="#{mon_page_href('reborn', sym)}">#{inner}</a>)
  end

  def row_html(row, hashes)
    # describe はエスケープ済みの HTML を返す (どうぐ名は店の索引への
    # リンクになっている)。
    text = EvolutionIndex.describe(row, hashes[:item], hashes[:move], hashes[:mon], hashes[:map])
    group = EvolutionIndex.group(row[:method])
    form_index = hashes[:mon][row[:from]].keys.select { |k| k.is_a?(String) }.index(row[:form]) || 0

    <<~ROW
      <tr data-group="#{group}" data-name="#{esc(EvolutionIndex.species_name(row[:from], hashes[:mon]))}">
        <td class="ev-from">#{mon_cell(row[:from], hashes[:mon], form_index)}</td>
        <td class="ev-arrow">→</td>
        <td class="ev-to">#{mon_cell(row[:to], hashes[:mon])}</td>
        <td class="ev-how">#{text}</td>
      </tr>
    ROW
  end

  def filter_html(rows)
    ja = JaNames.enabled?
    labels = ja ? GROUP_LABELS : GROUP_LABELS_EN
    counts = Hash.new(0)
    rows.each { |r| counts[EvolutionIndex.group(r[:method])] += 1 }

    chips = %w[level item trade happiness location other].filter_map { |g|
      next if counts[g].zero?

      %(<button type="button" class="ref-chip ev-chip" data-value="#{g}">) +
        %(#{esc(labels[g])}<span>#{counts[g]}</span></button>)
    }.join

    <<~BAR
      <div class="ref-filter ev-filter" hidden>
        <div class="ref-filter-line">
          <input type="search" id="ev-q" class="ref-search" autocomplete="off"
                 placeholder="#{ja ? '種族名・どうぐ名・わざ名で絞る' : 'Filter by species, item or move'}">
          <span class="ref-count" role="status" aria-live="polite"></span>
          <button type="button" class="ref-reset">#{ja ? '条件を外す' : 'Clear'}</button>
        </div>
        <div class="ref-filter-line ref-chips" data-group="groups">
          <span class="ref-chip-label">#{ja ? '進化の仕方' : 'Method'}</span>#{chips}
        </div>
      </div>
    BAR
  end

  def build_page(game, item_hash, move_hash, pokemon_hash, map_hash)
    rows = EvolutionIndex.collect(pokemon_hash)
    return nil if rows.empty?

    hashes = { item: item_hash, move: move_hash, mon: pokemon_hash, map: map_hash }
    trade = rows.count { |r| EvolutionIndex.group(r[:method]) == 'trade' }
    title = JaNames.enabled? ? '進化条件の一覧' : 'Evolution Methods'

    lead =
      if JaNames.enabled?
        ["ゲームのデータから起こした進化条件の一覧です。#{rows.length}件。" \
         "種族名を押すと、その種族の頁へ飛べます。",
         "通信交換で進化するものが#{trade}件あります。" \
         "条件の読み方は Evolution.rb の判定に合わせてあり、" \
         "「なつき度を上げて」は220以上を指します。"]
      else
        ["Evolution methods taken from the game data. #{rows.length} entries, #{trade} of them by trade. " \
         "Open a species for its own page."]
      end

    <<~PAGE
      ---
      title: #{title}
      permalink: /#{game}/evolutions/
      ---

      <p id="title-text">#{title}</p>

      <p class="ref-back"><a href="/#{game}/">#{JaNames.ui('Back to contents')}</a></p>

      #{lead[0]}

      #{lead[1]}

      #{filter_html(rows)}

      <table class="ev-table">
      #{rows.map { |r| row_html(r, hashes) }.join}
      </table>
    PAGE
  end
end
