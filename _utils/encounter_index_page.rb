# frozen_string_literal: true

require_relative 'ja_names'
require_relative 'encounter_index'
require_relative 'doc_context'

# 「この種族はどこで捕まえられるか」の一覧ページ。
#
# 表そのものは EncounterIndex が本文の出現表から1行ずつ受け取っている
# (実測 2,529行 / 595種)。ここではそれを種族ごとに並べ替えて出すだけ。
#
# 生 HTML で書くのは、種族名に markdown の装飾が入らないため。項目数が多く
# (種族595 × 平均4.2箇所)、kramdown の表に流すより構造を作り込める。
module EncounterIndexPage
  module_function

  # 出現方法の並び。表の列に出ていた時間帯・釣り竿の札。
  RATE_UI = {
    'morning' => 'morning', 'day' => 'day', 'night' => 'night',
    'oldrod' => 'oldrod', 'goodrod' => 'goodrod', 'superrod' => 'superrod'
  }.freeze

  BLOCK = 100

  def esc(text)
    text.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;').gsub('"', '&quot;')
  end

  def chapter_label(title)
    m = title.to_s.match(/\A(.+?)[:：]/)
    m ? m[1].strip : title.to_s.strip
  end

  # 「どうくつ · Lv2-9 · 71%」のような but 添え書き。時間帯で率が違う表は
  # 「朝 12% / 昼 12% / 夜 5%」のように札を添える。
  def meta(place)
    parts = []
    parts << "Lv#{esc(place[:levels])}" if place[:levels].to_s != ''

    rates = place[:rates].reject { |_, v| v.to_i.zero? }
    unless rates.empty?
      parts << rates.map { |label, value|
        label ? "#{JaNames.ui(RATE_UI[label] || label)} #{value}%" : "#{value}%"
      }.join(' / ')
    end
    parts.join(' · ')
  end

  # 出現方法の札。表の色分けと同じ考え方で、走査したときに方法が拾えるように
  # する。td が white-space: pre-line なので、改行を入れずに1行で書く。
  GROUP_CLASS = {
    'くさむら' => 'grass', 'どうくつ' => 'cave', 'なみのり' => 'surf',
    'ヘッドバット' => 'headbutt', 'いわくだき' => 'smash', 'つり' => 'fish',
    'Grass' => 'grass', 'Cave' => 'cave', 'Surfing' => 'surf',
    'Headbutt' => 'headbutt', 'Rock Smash' => 'smash', 'Fishing' => 'fish'
  }.freeze

  # 絞り込みチップの表示名。表に出ている札と同じ言葉にする。
  def self.way_labels
    keys = %w[Grass Cave Surfing Headbutt Rock\ Smash Fishing]
    keys.to_h { |k| [JaNames.ui(k), GROUP_CLASS[k]] }
  end

  def place_html(place)
    ctx = place[:context] || {}
    chapter = chapter_label(ctx[:chapter])
    link = ctx[:href] ? %(<a href="#{ctx[:href]}">#{esc(place[:map_label])}</a>) : esc(place[:map_label])
    cls = GROUP_CLASS[place[:group]] || 'other'
    badge = %(<span class="pdx-way pdx-way-#{cls}">#{esc(place[:group])}</span>)
    "<li data-way=\"#{cls}\" data-ch=\"#{ctx[:seq] || 0}\">#{badge}#{link} <span class=\"pdx-meta\">" \
      "#{chapter.empty? ? '' : "#{esc(chapter)} · "}#{meta(place)}</span></li>"
  end

  # ゲーム内のタイプの並び。チップの並び順に使う。辞書順だと「ノーマル・
  # ほのお・みず…」の見慣れた並びから外れる。
  def type_order(scripts_dir)
    @type_order ||= begin
      path = scripts_dir ? File.join(scripts_dir, 'Reborn', 'typetext.rb') : nil
      src = path && File.exist?(path) ? File.read(path) : ''
      src.scan(/^  :([A-Z]+) =>/).flatten.map(&:downcase)
    end
  end

  # 種族への飛び先。付録の持ち物の表から辿れるようにする。
  # 姿違い (アローラのすがた など) は同じ内部シンボルを共有するので、
  # 最初に出てきた1行にだけ付ける。
  def anchor_for(entry)
    @anchored ||= {}
    key = entry[:species_key].to_s.downcase
    return '' if key.empty? || @anchored[key]

    @anchored[key] = true
    %( id="mon-#{key}")
  end

  def species_html(entry)
    icon = if entry[:icon]
             %(<img src="#{entry[:icon]}" alt="" class="mon-icon pdx-icon" ) +
               %(loading="lazy" width="32" height="32">)
           else
             ''
           end
    # 野生個体が持っていることのある道具。付録の表と同じ出典で、捕まえる
    # 場所を見ているその場で「盗む価値があるか」が分かる。
    held = Array(entry[:held]).map { |name, pct|
      %(<span class="pdx-held-item">#{esc(name)}<span>#{pct}%</span></span>)
    }.join
    held = %(<div class="pdx-held">#{held}</div>) unless held.empty?

    only_label = JaNames.enabled? ? '1箇所のみ' : 'only here'
    only = entry[:places].length == 1 ? %( <span class="pdx-only">#{only_label}</span>) : ''
    types = Array(entry[:types]).map { |t|
      name = JaNames.tr('types', t.to_s.capitalize)
      %(<span class="type-badge type-#{t.to_s.downcase}">#{esc(name)}</span>)
    }.join

    ways = entry[:places].map { |p| GROUP_CLASS[p[:group]] || 'other' }.uniq.join(' ')
    kinds = Array(entry[:types]).map { |t| t.to_s.downcase }.join(' ')
    # 一番早く行ける場所の章。「ここまで進んだ」の絞り込みに使う。
    first_ch = entry[:places].map { |p| p.dig(:context, :seq) || 0 }.min

    <<~ROW
      <tr#{anchor_for(entry)} data-name="#{esc(entry[:species])}" data-en="#{esc(entry[:species_key].to_s.downcase)}" data-types="#{kinds}" data-ways="#{ways}" data-only="#{entry[:places].length == 1 ? 1 : 0}" data-ch="#{first_ch}">
        <td class="pdx-mon">#{icon}<span class="pdx-name">#{esc(entry[:species])}</span><span class="pdx-dex">No.#{entry[:dexnum]}</span><span class="pdx-types">#{types}</span>#{only}#{held}</td>
        <td class="pdx-places"><ul>#{entry[:places].map { |p| place_html(p) }.join}</ul></td>
      </tr>
    ROW
  end

  def block_of(dexnum)
    ((dexnum - 1) / BLOCK) * BLOCK + 1
  end

  def block_label(start)
    "No.#{start}–#{start + BLOCK - 1}"
  end

  # 絞り込みの操作子。JavaScript が動いたときだけ出す (hidden を外す)。
  # 切っていても表は全件そのまま残るので、ブラウザの検索は今までどおり効く。
  def filter_html(species, scripts_dir)
    type_counts = Hash.new(0)
    way_counts = Hash.new(0)
    species.each do |sp|
      Array(sp[:types]).map { |t| t.to_s.downcase }.uniq.each { |t| type_counts[t] += 1 }
      sp[:places].map { |pl| GROUP_CLASS[pl[:group]] || 'other' }.uniq.each { |w| way_counts[w] += 1 }
    end

    order = type_order(scripts_dir)
    types = type_counts.keys.sort_by { |t| [order.index(t) || 99, t] }
    type_chips = types.map { |t|
      label = JaNames.tr('types', t.capitalize)
      %(<button type="button" class="ref-chip type-badge type-#{t}" data-value="#{t}">) +
        %(#{esc(label)}<span>#{type_counts[t]}</span></button>)
    }.join

    ways = way_counts.keys.sort_by { |w| -way_counts[w] }
    way_chips = ways.map { |w|
      label = way_labels.key(w) || w
      %(<button type="button" class="ref-chip pdx-way pdx-way-#{w}" data-value="#{w}">) +
        %(#{esc(label)}<span>#{way_counts[w]}</span></button>)
    }.join

    only = species.count { |sp| sp[:places].length == 1 }
    ja = JaNames.enabled?

    # 「ここまで進んだ」の選択肢。出現表が載っている章だけを、本文の順で出す。
    options = DocContext.progress_chapters.map { |i, title|
      %(<option value="#{i}">#{esc(chapter_label(title))}</option>)
    }.join

    <<~BAR
      <div class="ref-filter" hidden>
        <div class="ref-filter-line">
          <input type="search" id="pdx-q" class="ref-search" autocomplete="off"
                 placeholder="#{ja ? '名前・タイプ・地名で絞る（かな・英語名も可）' : 'Filter by name, type or place'}">
          <span class="ref-count" role="status" aria-live="polite"></span>
        </div>
        <div class="ref-filter-line ref-chips" data-group="types">
          <span class="ref-chip-label">#{ja ? 'タイプ' : 'Type'}</span>#{type_chips}
        </div>
        <div class="ref-filter-line ref-chips" data-group="ways">
          <span class="ref-chip-label">#{ja ? '出現方法' : 'Method'}</span>#{way_chips}
        </div>
        <div class="ref-filter-line">
          <label class="ref-toggle" for="pdx-upto">#{ja ? 'ここまで進んだ' : 'Progress'}</label>
          <select id="pdx-upto" class="ref-select">
            <option value="">#{ja ? '全部見る' : 'All chapters'}</option>
            #{options}
          </select>
          <label class="ref-toggle"><input type="checkbox" id="pdx-only">
            #{ja ? "出現する場所が1箇所だけ" : 'Only one place'}<span>#{only}</span></label>
          <label class="ref-toggle" for="pdx-sort">#{ja ? '並び' : 'Order'}</label>
          <select id="pdx-sort" class="ref-select">
            <option value="dex">#{ja ? '図鑑番号' : 'Dex number'}</option>
            <option value="kana">#{ja ? '五十音' : 'A-Z'}</option>
          </select>
          <button type="button" class="ref-reset">#{ja ? '条件を外す' : 'Clear'}</button>
        </div>
      </div>
    BAR
  end

  def build_page(game, scripts_dir = nil)
    species = EncounterIndex.by_species
    return nil if species.empty?

    blocks = species.group_by { |s| block_of(s[:dexnum]) }.sort_by(&:first)

    jump = blocks.map { |start, list|
      %(<li><a href="#dex-#{start}">#{block_label(start)}<span>#{list.length}</span></a></li>)
    }.join("\n  ")

    sections = blocks.map do |start, list|
      <<~SECTION
        ## #{block_label(start)} {#dex-#{start}}

        <table class="pdx-table">
        #{list.map { |s| species_html(s) }.join}
        </table>

      SECTION
    end

    total_places = species.sum { |s| s[:places].length }
    only_one = species.count { |s| s[:places].length == 1 }

    title = JaNames.enabled? ? 'ポケモンの出現場所' : 'Wild Encounters'
    lead =
      if JaNames.enabled?
        ["攻略本文にある出現表を、種族から引けるように並べ替えたものです。" \
         "#{species.length}種 / #{total_places}箇所。場所名を押すと、その表が載っている本文へ飛べます。",
         "場所は本文に出てくる順、つまり早く行ける順に並べています。" \
         "#{only_one}種は出現する場所が1箇所しかないので、印を付けました。",
         "下の欄で、名前・タイプ・地名から絞り込めます。名前はひらがな（ふしぎだね）でも" \
         "英語名（bulbasaur）でも引けます。/ キーで入力欄に移れます。" \
         "絞り込んだ状態は URL に残るので、そのまま人に渡せます。",
         "野生で出会える場所だけを載せています。もらえる個体・固定シンボル・タマゴ・交換で手に入るものは含みません。"]
      else
        ["The walkthrough's encounter tables, rearranged by species. " \
         "#{species.length} species / #{total_places} places.",
         "Places are listed in walkthrough order, so the earliest one comes first. " \
         "#{only_one} species appear in exactly one place.",
         "Use the box below to filter by name, type or place. Press / to jump to it.",
         "Wild encounters only - gifts, static encounters, eggs and trades are not listed."]
      end

    <<~PAGE
      ---
      title: #{title}
      permalink: /#{game}/pokemon/
      ---

      <p id="title-text">#{title}</p>

      <p class="ref-back"><a href="/#{game}/">#{JaNames.ui('Back to contents')}</a></p>

      #{lead[0]}

      #{lead[1]}

      #{lead[2]}

      #{lead[3]}
      {: .pdx-note}

      #{filter_html(species, scripts_dir)}

      <nav class="affinity-jump pdx-jump">
        <ul>
        #{jump}
        </ul>
      </nav>

      #{sections.join("\n")}
    PAGE
  end
end
