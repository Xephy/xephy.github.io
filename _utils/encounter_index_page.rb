# frozen_string_literal: true

require_relative 'ja_names'
require_relative 'encounter_index'

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

  def place_html(place)
    ctx = place[:context] || {}
    chapter = chapter_label(ctx[:chapter])
    link = ctx[:href] ? %(<a href="#{ctx[:href]}">#{esc(place[:map_label])}</a>) : esc(place[:map_label])
    cls = GROUP_CLASS[place[:group]] || 'other'
    badge = %(<span class="pdx-way pdx-way-#{cls}">#{esc(place[:group])}</span>)
    "<li>#{badge}#{link} <span class=\"pdx-meta\">" \
      "#{chapter.empty? ? '' : "#{esc(chapter)} · "}#{meta(place)}</span></li>"
  end

  def species_html(entry)
    icon = if entry[:icon]
             %(<img src="#{entry[:icon]}" alt="" class="mon-icon pdx-icon" ) +
               %(loading="lazy" width="32" height="32">)
           else
             ''
           end
    only_label = JaNames.enabled? ? '1箇所のみ' : 'only here'
    only = entry[:places].length == 1 ? %( <span class="pdx-only">#{only_label}</span>) : ''
    types = Array(entry[:types]).map { |t|
      name = JaNames.tr('types', t.to_s.capitalize)
      %(<span class="type-badge type-#{t.to_s.downcase}">#{esc(name)}</span>)
    }.join

    <<~ROW
      <tr>
        <td class="pdx-mon">#{icon}<span class="pdx-name">#{esc(entry[:species])}</span><span class="pdx-dex">No.#{entry[:dexnum]}</span><span class="pdx-types">#{types}</span>#{only}</td>
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

  def build_page(game)
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
         "#{only_one}種は出現する場所が1箇所しかないので、印を付けました。" \
         "種族名で探すときはブラウザの検索（Ctrl+F / ⌘+F）が早いです。",
         "野生で出会える場所だけを載せています。もらえる個体・固定シンボル・タマゴ・交換で手に入るものは含みません。"]
      else
        ["The walkthrough's encounter tables, rearranged by species. " \
         "#{species.length} species / #{total_places} places.",
         "Places are listed in walkthrough order, so the earliest one comes first. " \
         "#{only_one} species appear in exactly one place.",
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
      {: .pdx-note}

      <nav class="affinity-jump pdx-jump">
        <ul>
        #{jump}
        </ul>
      </nav>

      #{sections.join("\n")}
    PAGE
  end
end
