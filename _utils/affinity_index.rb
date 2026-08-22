# frozen_string_literal: true

require 'json'
require_relative 'ja_names'

# 好感度の選択肢を1ページに集める。
#
# 選択肢は本編と後日談の28章に散っていて、実測で 228ブロック / 311項目ある。
# 章を順に読んでいるだけでは「テラの好感度を上げたい」と思っても計画が
# 立てられないので、キャラクター別に組み直したページを別に作る。
#
# 元になるのは組み上がった章の本文 (Affinity.apply 済み)。増減は
# <span class="affinity-delta"> に包まれているため、生の括弧を読み直すより
# 確実に拾える。見出しの {#id} もそのまま残っているので、各項目から本文の
# 節へ戻すリンクが張れる。
module AffinityIndex
  module_function

  MARKER = '<!-- 好感度 -->'
  LIST_END = '{: .affinity-list}'
  DELTA_SPAN = %r{<span class="affinity-delta[^"]*">([^<]*)</span>}.freeze
  H1 = /\A\#[ \t]+(.+?)[ \t]*(?:\{\#([^}]+)\})?[ \t]*\z/.freeze
  H23 = /\A(\#{2,3})[ \t]+(.+?)[ \t]*\{\#([^}]+)\}[ \t]*\z/.freeze

  # "+1 カイン、-2 シェリー" を分解する。区切りは日本語版が「、」、
  # WT_LANG=en で生成したときのために半角カンマも見る。
  SEGMENT = /[、,]/.freeze
  ENTRY = /\A([+-]\d+)\s+(.+)\z/.freeze

  # 「-2 アヤ。これは選択肢ではありません」のように、増減のうしろへ注記が
  # 続くものが2件ある。人物名は句点までで切り、残りは注記として持つ。
  NOTE_SEP = '。'

  # dict.json の trainer_names に無い人物。シグムンドは戦闘トレーナーとして
  # 登場しないため辞書に載っていないが、好感度は動く。
  EXTRA_NAMES = { 'シグムンド' => 'Sigmund' }.freeze

  def name_to_en
    @name_to_en ||= begin
      rev = {}
      (JaNames.dict['trainer_names'] || {}).each { |en, ja| rev[ja] ||= en }
      EXTRA_NAMES.each { |ja, en| rev[ja] ||= en }
      rev
    end
  end

  # 見出しの id に使える ASCII を作る。日本語のままだと kramdown の
  # auto_ids が空に潰れるため、英語名から起こす。
  def slug_for(name)
    @slugs ||= {}
    @slugs[name] ||= begin
      en = name_to_en[name] || name
      base = en.downcase.gsub(/[^a-z0-9]+/, '-').gsub(/\A-|-\z/, '')
      # WT_LANG=en では辞書を読まないので英語名に戻せない。id が空に潰れて
      # 飛び先が壊れるため、そのときだけ連番で代用する。
      base = "p#{@slugs.length + 1}" if base.empty?
      "affinity-#{base}"
    end
  end

  # 章の本文から選択肢を取り出す。
  def collect(chapters, game)
    entries = []

    chapters.each_with_index do |chapter, chapter_index|
      base = "/#{game}/#{chapter[:slug]}/"
      section = nil
      lines = chapter[:content].to_s.split("\n", -1)
      i = 0

      while i < lines.length
        line = lines[i]

        if (m = line.match(H23))
          section = { text: m[2].strip, id: m[3] }
          i += 1
          next
        end

        unless line.strip == MARKER
          i += 1
          next
        end

        # ラベル行・IAL・空行を読み飛ばして、項目の先頭まで進める。
        i += 1
        i += 1 while i < lines.length && !lines[i].start_with?('- ') && lines[i].strip != LIST_END
        while i < lines.length && lines[i].start_with?('- ')
          entries << build_entry(lines[i][2..], chapter, chapter_index, base, section)
          i += 1
        end
        i += 1 while i < lines.length && lines[i].strip == LIST_END
      end
    end

    entries
  end

  def build_entry(raw_item, chapter, chapter_index, base, section)
    delta = raw_item[DELTA_SPAN, 1]
    text = raw_item.gsub(DELTA_SPAN, '').strip
    {
      chapter_index: chapter_index,
      chapter_title: chapter[:title],
      href: section ? "#{base}##{section[:id]}" : base,
      section: section ? section[:text] : chapter[:title],
      text: text,
      deltas: parse_deltas(delta)
    }
  end

  # 増減の中身を [{ name:, value:, note: }] にする。人物名を伴わない
  # 「増減なし」「会話4種それぞれ +1 アヤ、合計 +4」のような書き方は、
  # 人物名なしの注記として残す。
  def parse_deltas(inner)
    return [] if inner.nil? || inner.strip.empty?

    inner.split(SEGMENT).filter_map do |seg|
      s = seg.strip
      next if s.empty?

      m = s.match(ENTRY)
      next { name: nil, value: nil, note: s } unless m

      name = m[2].strip
      note = nil
      if (pos = name.index(NOTE_SEP))
        note = name[(pos + 1)..].strip
        name = name[0...pos].strip
      end
      { name: name, value: m[1].to_i, note: note }
    end
  end

  # 人物ごとにまとめる。並び順は初登場の章が早い順。読み進めた範囲より
  # 先の名前がページ上部に並ばないようにするため。
  def by_person(entries)
    people = {}

    entries.each do |entry|
      entry[:deltas].each do |d|
        next unless d[:name]

        p = (people[d[:name]] ||= { name: d[:name], rows: [], first: entry[:chapter_index] })
        p[:first] = [p[:first], entry[:chapter_index]].min
        p[:rows] << entry.merge(value: d[:value], note: d[:note])
      end
    end

    people.values.sort_by { |p| [p[:first], -p[:rows].length, p[:name]] }
  end
end

# ページの組み立て。表は kramdown のテーブル記法で書く。項目に
# *いやしのすず* のような装飾が4件あり、生 HTML で囲むと kramdown が
# 中の処理を止めてしまうため。
module AffinityIndex
  module_function

  CHAPTER_LABEL = /\A(.+?)[:：]/.freeze

  def short_chapter(title)
    m = title.to_s.match(CHAPTER_LABEL)
    m ? m[1].strip : title.to_s.strip
  end

  def esc(text)
    text.to_s.gsub('|', '\\|')
  end

  def sign(value)
    value.positive? ? "+#{value}" : value.to_s
  end

  # 本文の選択肢カードと同じ色分けの札にする。表を上から追うとき、
  # 数字だけだと上げ下げの判別に一拍かかる。
  def chip(value)
    tone = value.positive? ? 'is-up' : 'is-down'
    %(<span class="affinity-delta #{tone}">#{sign(value)}</span>)
  end

  # ある選択肢で同時に動く他の人物。取引になっている選択肢が多いので、
  # 本人の増減だけ見ても判断できない。
  def others(entry, self_name)
    entry[:deltas].filter_map do |d|
      next if d[:name].nil? || d[:name] == self_name

      "#{chip(d[:value])} #{d[:name]}"
    end.join(' ')
  end

  # 章の先頭 (最初の ## より前) にある選択肢は節を持たない。その場合に
  # 「エピソード13 / エピソード13: 奔流」と重ねて出さないようにする。
  def place(row)
    chapter = short_chapter(row[:chapter_title])
    label = row[:section] == row[:chapter_title] ? chapter : "#{chapter} / #{row[:section]}"
    "[#{esc(label)}](#{row[:href]})"
  end

  def person_rows(person)
    person[:rows].sort_by.with_index { |r, i| [r[:chapter_index], i] }.map do |r|
      delta = chip(r[:value])
      delta += "<span class=\"affinity-note\">#{esc(r[:note])}</span>" if r[:note]
      "| #{place(r)} | #{esc(r[:text])} | #{delta} | #{esc(others(r, person[:name]))} |"
    end
  end

  # 数値の増減を持たない選択肢 (「増減なし」や計算式で示されるもの)。
  # 人物別の表には居場所が無いので、最後にまとめて残す。
  def unnumbered(entries)
    entries.reject { |e| e[:deltas].any? { |d| d[:name] } }
  end

  def build_page(chapters, game)
    entries = collect(chapters, game)
    people = by_person(entries)
    return nil if people.empty?

    rest = unnumbered(entries)
    jump = people.map { |p|
      "<li><a href=\"##{slug_for(p[:name])}\">#{p[:name]}<span>#{p[:rows].length}</span></a></li>"
    }
    unless rest.empty?
      jump << "<li><a href=\"#affinity-others\">数値で表せない<span>#{rest.length}</span></a></li>"
    end
    jump = jump.join("\n  ")

    sections = people.map do |p|
      <<~PERSON
        ## #{p[:name]} {##{slug_for(p[:name])}}

        | 章・節 | 選択肢 | 増減 | 同時に動く |
        |---|---|---|---|
        #{person_rows(p).join("\n")}
        {: .affinity-table}

      PERSON
    end

    unless rest.empty?
      rows = rest.map { |r| "| #{place(r)} | #{esc(r[:text])} |" }
      sections << <<~REST
        ## 数値で表せない選択肢 {#affinity-others}

        増減が0のものと、計算式で示されるものです。

        | 章・節 | 選択肢 |
        |---|---|
        #{rows.join("\n")}
        {: .affinity-table}

      REST
    end

    <<~PAGE
      ---
      title: 好感度まとめ
      permalink: /#{game}/affinity/
      ---

      <p id="title-text">好感度まとめ</p>

      <p class="ref-back"><a href="/#{game}/">目次へ戻る</a></p>

      本編と後日談に出てくる好感度の選択肢を、人物ごとに並べ直したものです。攻略本文から自動で作っているので、各行の左端から本文の該当箇所へ戻れます。人物 #{people.length}名 / 選択肢 #{entries.length}件。

      多くの選択肢は取引になっていて、誰かを上げると別の誰かが下がります。「同時に動く」の欄で先に確かめてから決めてください。

      **ネタバレ注意** — 終盤まで登場しない人物の名前と、展開が分かる選択肢が並んでいます。
      {: .affinity-warning}

      <nav class="affinity-jump">
        <ul>
        #{jump}
        </ul>
      </nav>

      #{sections.join("\n")}
    PAGE
  end
end
