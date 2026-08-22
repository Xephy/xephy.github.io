# frozen_string_literal: true

require_relative 'ja_names'
require_relative 'machine_index'
require_relative 'doc_context'

# わざマシン・ひでんマシンの一覧ページ。
module MachineIndexPage
  module_function

  def esc(text)
    text.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;').gsub('"', '&quot;')
  end

  def chapter_label(title)
    m = title.to_s.match(/\A(.+?)[:：]/)
    m ? m[1].strip : title.to_s.strip
  end

  def type_badge(sym)
    t = sym.to_s.downcase
    label = sym == :QMARKS ? '???' : JaNames.tr('types', sym.to_s.capitalize)
    cls = sym == :QMARKS ? 'qmarks' : t
    %(<span class="type-badge type-#{cls}">#{esc(label)}</span>)
  end

  # 分類・威力・命中。変化わざは威力を持たないので出さない。
  def move_meta(move)
    parts = [JaNames.ui(move[:category].to_s.capitalize)]
    parts << "#{move[:basedamage]}" if move[:basedamage].to_i.positive?
    parts << (move[:accuracy].to_i.zero? ? JaNames.ui('Perfect') : "#{move[:accuracy]}%")
    parts.join(' · ')
  end

  def row_html(row, places, seq_of)
    move = row[:move]
    items = places.map { |s|
      chapter = chapter_label(s[:chapter])
      %(<li data-ch="#{seq_of[s[:chapter]] || 0}"><a href="#{s[:href]}">#{esc(s[:text])}</a>) +
        %( <span class="tm-meta">#{esc(chapter)}</span></li>)
    }
    first_ch = places.map { |s| seq_of[s[:chapter]] || 0 }.min || 999
    where = items.empty? ? %(<span class="tm-none">本文に記載なし</span>) : "<ul>#{items.join}</ul>"

    <<~ROW
      <tr data-name="#{esc(row[:label])}" data-move="#{esc(move[:name])}" data-types="#{move[:type].to_s.downcase}" data-ch="#{first_ch}" data-has="#{items.empty? ? 0 : 1}">
        <td class="tm-no"><em>#{esc(row[:label])}</em></td>
        <td class="tm-move">#{type_badge(move[:type])}<strong>#{esc(move[:name])}</strong><span class="tm-meta">#{move_meta(move)}</span></td>
        <td class="tm-where">#{where}</td>
      </tr>
    ROW
  end

  def filter_html(rows, types)
    ja = JaNames.enabled?
    order = types.keys.sort_by { |t| [TYPE_ORDER.index(t) || 99, t] }
    chips = order.map { |t|
      label = t == 'qmarks' ? '???' : JaNames.tr('types', t.capitalize)
      %(<button type="button" class="ref-chip type-badge type-#{t}" data-value="#{t}">) +
        %(#{esc(label)}<span>#{types[t]}</span></button>)
    }.join

    options = DocContext.progress_chapters.map { |i, title|
      %(<option value="#{i}">#{esc(chapter_label(title))}</option>)
    }.join

    # 本文が入手に触れていないもの。いまは0本なので切り替えは出さない。
    missing = rows.count { |r| r[:places].empty? }
    missing_toggle =
      if missing.zero?
        ''
      else
        %(<label class="ref-toggle"><input type="checkbox" id="tm-missing">) +
          %(#{ja ? '本文に記載なし' : 'Not in the walkthrough'}<span>#{missing}</span></label>)
      end

    <<~BAR
      <div class="ref-filter tm-filter" hidden>
        <div class="ref-filter-line">
          <input type="search" id="tm-q" class="ref-search" autocomplete="off"
                 placeholder="#{ja ? '番号・わざ名・地名で絞る' : 'Filter by number, move or place'}">
          <span class="ref-count" role="status" aria-live="polite"></span>
        </div>
        <div class="ref-filter-line ref-chips" data-group="types">
          <span class="ref-chip-label">#{ja ? 'タイプ' : 'Type'}</span>#{chips}
        </div>
        <div class="ref-filter-line">
          <label class="ref-toggle" for="tm-upto">#{ja ? 'ここまで進んだ' : 'Progress'}</label>
          <select id="tm-upto" class="ref-select">
            <option value="">#{ja ? '全部見る' : 'All chapters'}</option>
            #{options}
          </select>
          #{missing_toggle}
          <button type="button" class="ref-reset">#{ja ? '条件を外す' : 'Clear'}</button>
        </div>
      </div>
    BAR
  end

  TYPE_ORDER = %w[normal fighting flying poison ground rock bug ghost steel qmarks
                  fire water grass electric psychic ice dragon dark fairy shadow].freeze

  def build_page(game, item_hash, move_hash, chapters)
    machines = MachineIndex.build(item_hash, move_hash)
    return nil if machines.empty?

    found = MachineIndex.locations(chapters, game, machines.map { |m| m[:label] })
    seq_of = DocContext.chapters.each_with_index.to_h { |t, i| [t, i] }

    rows = machines.map { |m| m.merge(places: (found[m[:label]] || {}).values) }
    types = Hash.new(0)
    rows.each { |r| types[r[:move][:type].to_s.downcase] += 1 }

    with_place = rows.count { |r| r[:places].any? }
    title = JaNames.enabled? ? 'わざマシン一覧' : 'TM & HM List'

    lead =
      if JaNames.enabled?
        ["番号とわざの対応、それに攻略本文での入手場所をまとめたものです。" \
         "全#{rows.length}本（わざマシン#{rows.count { |r| r[:kind].zero? }} / " \
         "ひでんマシン#{rows.count { |r| r[:kind] == 1 }}）。" \
         "場所を押すと、その箇所の本文へ飛べます。",
         "番号とわざの対応はゲームのデータから、入手場所は攻略本文から取っています。" \
         "同じマシンが複数の場所に出てくることもあります" \
         "（買える店・落ちている場所・もらえる場面）。"]
      else
        ["TM/HM numbers, the move each teaches, and where the walkthrough mentions them. " \
         "#{rows.length} machines, #{with_place} with a location."]
      end

    <<~PAGE
      ---
      title: #{title}
      permalink: /#{game}/tms/
      ---

      <p id="title-text">#{title}</p>

      <p class="ref-back"><a href="/#{game}/">#{JaNames.ui('Back to contents')}</a></p>

      #{lead[0]}

      #{lead[1]}

      #{filter_html(rows, types)}

      <table class="tm-table">
      #{rows.map { |r| row_html(r, r[:places], seq_of) }.join}
      </table>
    PAGE
  end
end
