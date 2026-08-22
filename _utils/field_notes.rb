# frozen_string_literal: true

require 'json'
require_relative 'ja_names'
require_relative 'field_usage'

# ゲーム内アプリ「フィールドノート」を1ページに起こす。
#
# 攻略本文は 471箇所の戦闘で「フィールド: ○○」と書いているのに、それが何を
# するフィールドかはどこにも書かれていない。読者はゲームを開き直すか英語の
# Wiki を見るしかなかった。
#
# 元データは3つ。
#   1. Data/fieldnotes.dat  … ゲームが初回起動時に組み上げた解説文 (英語)。
#      1行ごとに :fieldeffect が付いているので、フィールド別に束ねられる。
#      Scripts/Reborn/FieldNoteCompiler.rb を再実行するより確実で速い。
#   2. _ja/field-notes.json … 日本語化パッチの訳 (英語原文がキー)。
#   3. Scripts/Reborn/fieldtext.rb … フィールドの表示名。eval には PBStats が
#      要るので、名前だけ正規表現で読む。
#
# 本文は <icon=...> <c=...> の独自記法で書かれている。ゲームの画像を持ち込むと
# タイプ名が英語のままになるうえ (typeFIRE.png は "FIRE" と描いてある)、
# 状態異常も BRN / SLP の英略語なので、サイト側の .type-badge と同じ方式で
# 文字と色で描き直す。
class PBFieldNote
  attr_accessor :fieldeffect, :text, :elaboration, :cogwheeltext
end

module FieldNotes
  module_function

  NOTES_JSON = File.expand_path('../_ja/field-notes.json', __dir__)

  # <icon=名前> の描き方。値は [表示する文字, CSS クラス]。
  # 色はゲームのアイコン画像から拾った実際の色を、白背景で読める明度まで
  # 落としたもの (style.scss 側に定義)。
  ICONS = {
    'fieldUp' => ['↑', 'fn-icon fn-up'],
    'fieldDown' => ['↓', 'fn-icon fn-down'],
    'fieldRedUp' => ['↑', 'fn-icon fn-redup'],
    'fieldChange' => ['→', 'fn-icon fn-change'],
    'fieldPlus' => ['＋', 'fn-icon fn-plus'],
    'field' => ['◆', 'fn-icon fn-field'],
    'fieldAllStat' => ['状態異常', 'fn-status fn-allstat'],
    'fieldBurn' => ['やけど', 'fn-status fn-burn'],
    'fieldSleep' => ['ねむり', 'fn-status fn-sleep'],
    'fieldFreeze' => ['こおり', 'fn-status fn-freeze'],
    'fieldParalyze' => ['まひ', 'fn-status fn-paralyze'],
    'fieldPoisonStatus' => ['どく', 'fn-status fn-poison'],
    'fieldNoSleep' => ['ねむらない', 'fn-status fn-no'],
    'fieldNoFreeze' => ['こおらない', 'fn-status fn-no'],
    'fieldFaint' => ['ひんし', 'fn-status fn-faint'],
    # ゲームデータ側に小文字の綴り違いが1件ある (どうくつフィールド)。
    'fieldfaint' => ['ひんし', 'fn-status fn-faint']
  }.freeze

  # <icon=typeXXX> のタイプ名。dict.json の types は "Electric" のような
  # 先頭大文字がキーなので、シンボル側を寄せる。??? は訳語を持たない。
  TYPE_NAMES = {
    'QMARKS' => '???'
  }.freeze

  COLORS = { 'green' => 'fn-green', 'orange' => 'fn-orange', 'red' => 'fn-red' }.freeze

  # 本文末尾の「続きがある」印。web では続きを下の行にそのまま出すので外す。
  CONTINUES = /\s*\.\s*\.\s*\.\s*\z/.freeze
  LEADS_ON = /\A\s*\.\s*\.\s*\.\s*/.freeze

  # WT_LANG=en では訳を当てない。元データ (fieldnotes.dat) が英語なので、
  # 引かなければそのまま英語版のページになる。
  def dict
    @dict ||= if JaNames.enabled? && File.exist?(NOTES_JSON)
                JSON.parse(File.read(NOTES_JSON))['notes'] || {}
              else
                {}
              end
  end

  # ゲームの行送りに合わせて和文の途中に入れてある空白。1,851箇所 / 817行
  # あり、画面幅の決まっていない web ではただの隙間になる。両側が非 ASCII の
  # ものだけ詰めるので、タグの前後や英数字まわりの空白はそのまま残る。
  JA_SPACE = /(?<=[^\x00-\x7F])[ \t]+(?=[^\x00-\x7F])/.freeze
  UNIT_SPACE = /(?<=\d)[ \t]+(?=%)/.freeze

  def tighten(text)
    text.gsub(JA_SPACE, '').gsub(UNIT_SPACE, '')
  end

  def tr(text)
    return nil if text.nil?

    s = text.to_s
    return nil if s.strip.empty?

    tighten(dict[s.strip] || dict[s] || s.strip)
  end

  # fieldtext.rb からキーと表示名を順に読む。両者は1対1で並んでいる。
  def names(scripts_dir)
    @names ||= begin
      path = File.join(scripts_dir, 'Reborn', 'fieldtext.rb')
      src = File.exist?(path) ? File.read(path) : ''
      keys = src.scan(/^  :([A-Z_0-9]+) =>/).flatten
      vals = src.scan(/^    :name => "([^"]*)",/).flatten
      keys.zip(vals).to_h
    end
  end

  def load_notes(scripts_dir)
    @load_notes ||= begin
      path = File.expand_path('../Data/fieldnotes.dat', scripts_dir)
      File.exist?(path) ? Marshal.load(File.binread(path)) : []
    end
  end

  # 花畑フィールドだけ FLOWERGARDEN1〜5 の5キーが同じ表示名を持ち、解説文は
  # 4 に集約されている。末尾の数字を落として1本の節にする。
  def anchor(key)
    "field-#{key.to_s.downcase.sub(/\d+\z/, '')}"
  end

  # 解説文を持つフィールドのキーを fieldtext.rb の並び順で返す。
  def note_keys(scripts_dir)
    @note_keys ||= begin
      grouped = load_notes(scripts_dir).group_by(&:fieldeffect)
      names(scripts_dir).keys.map(&:to_sym).select { |k| grouped[k] && !grouped[k].empty? }
    end
  end

  # 名前 -> キーの逆引き。解説文を持つキーだけで作るので、花畑の5キーは
  # 自動的に FLOWERGARDEN4 に寄る。
  #
  # 攻略本文からは英語名で渡ってくるが、バトルタワー系の生成だけは
  # 訳し終えた日本語名で渡ってくる (実測 240箇所)。両方を入口にする。
  def name_index(scripts_dir)
    @name_index ||= begin
      table = names(scripts_dir)
      idx = {}
      note_keys(scripts_dir).each do |k|
        en = table[k.to_s].to_s
        next if en.strip.empty?

        idx[en] ||= k
        idx[en.sub(/\s+(Field|Arena)\z/, '')] ||= k
        ja = JaNames.field(en)
        idx[ja] ||= k if ja.is_a?(String)
      end
      idx
    end
  end

  # 攻略本文が書いているフィールド名 ("Forest Field" など) をキーに戻す。
  # 表記ゆれの吸収は JaNames と同じ規則を使う。"A atop B" は主となる A を採る。
  def key_for(name, scripts_dir)
    return nil unless name.is_a?(String)

    head = name.split(/\s+atop\s+|\s+upon\s+|\s+OR\s+/, 2).first.to_s.strip
    head = JaNames.field_alias(head) || head
    idx = name_index(scripts_dir)
    idx[head] || idx[head.sub(/\s+(Field|Arena)\z/, '')] || idx["#{head} Field"]
  end
end

# 本文の描画とページ組み立て。
module FieldNotes
  module_function

  require 'strscan'

  TOKEN = %r{</c>|<c=([^>]*)>|<icon=([A-Za-z]+)(?:,tts="([^"]*)")?>}.freeze

  def escape(text)
    text.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;').gsub('"', '&quot;')
  end

  # 表示名 -> キー。フィールドが別のフィールドに変わる行 (実測24行) を
  # 相手の節へ繋ぐのに使う。
  def display_index(scripts_dir)
    @display_index ||= begin
      table = names(scripts_dir)
      note_keys(scripts_dir).to_h { |k| [display_name(k, table), k] }
    end
  end

  # 素の文字列の断片が、そのまま別のフィールドの名前になっているときだけ
  # リンクにする。部分一致だと「どうくつ」が「クリスタルのどうくつ」の中に
  # 当たるので、断片まるごとの一致だけを見る。
  def link_field(chunk, scripts_dir, self_key)
    return escape(chunk) unless scripts_dir

    key = display_index(scripts_dir)[chunk.strip]
    return escape(chunk) if key.nil? || key == self_key

    lead, body, tail = chunk.partition(chunk.strip)
    "#{escape(lead)}<a href=\"##{anchor(key)}\">#{escape(body)}</a>#{escape(tail)}"
  end

  def type_label(sym)
    TYPE_NAMES[sym] || JaNames.tr('types', sym.capitalize)
  end

  def icon_html(name, tts)
    # 読み上げ用の語 (tts) がある行は、アイコンが動詞の代わりになっている。
    # 見た目は記号のまま、支援技術には元の語を渡す。
    title = tts && !tts.empty? ? %( title="#{escape(tts)}") : ''

    if name.start_with?('type')
      sym = name.sub(/\Atype/, '')
      label = type_label(sym)
      cls = sym == 'QMARKS' ? 'qmarks' : sym.downcase
      return %(<span class="type-badge type-#{cls}"#{title}>#{escape(label)}</span>)
    end

    glyph, cls = ICONS[name]
    unless glyph
      warn "未対応のフィールドノート記号: #{name}"
      return escape(name)
    end

    %(<span class="#{cls}"#{title}>#{escape(glyph)}</span>)
  end

  # <c=...> と <icon=...> を HTML にする。入れ子が無いことは実データで確認済み。
  def render(text, scripts_dir = nil, self_key = nil)
    return '' if text.nil?

    s = StringScanner.new(text.to_s)
    out = +''
    until s.eos?
      chunk = s.scan_until(TOKEN)
      unless chunk
        out << link_field(s.rest, scripts_dir, self_key)
        break
      end

      out << link_field(chunk[0...(chunk.length - s.matched.length)], scripts_dir, self_key)
      color, icon, tts = s[1], s[2], s[3]
      out << if s.matched == '</c>'
               '</span>'
             elsif icon
               icon_html(icon, tts)
             elsif COLORS.key?(color)
               %(<span class="fn-c #{COLORS[color]}">)
             else
               # 花畑フィールドの段階 (1〜5) を色で示している箇所。中身は数字
               # そのものなので、色に頼らず段階の札として描く。
               '<span class="fn-c fn-stage">'
             end
    end
    out.strip
  end

  def note_html(note, scripts_dir = nil)
    key = note.fieldeffect
    main = tr(note.text).to_s.sub(CONTINUES, '')
    body = +%(<span class="fn-main">#{render(main, scripts_dir, key)}</span>)

    cog = tr(note.cogwheeltext)
    body << %( <span class="fn-cog">#{render(cog, scripts_dir, key)}</span>) if cog

    more = tr(note.elaboration)
    if more
      body << %(<span class="fn-more">) +
              render(more.sub(LEADS_ON, ''), scripts_dir, key).gsub("\n", '<br>') +
              '</span>'
    end

    # タイプの札が入っている行は、タイプで絞り込めるようにする。
    kinds = body.scan(/type-badge type-([a-z]+)/).flatten.uniq.join(' ')
    %(<li#{kinds.empty? ? '' : %( data-types="#{kinds}")}>#{body}</li>)
  end

  # 絞り込みの操作子。出現場所ページと同じ体裁 (.ref-*) を使う。
  # JavaScript が動いたときだけ hidden を外すので、切っていても820行は
  # そのまま残る。
  def filter_html(notes, scripts_dir)
    counts = Hash.new(0)
    notes.each do |n|
      html = [n.text, n.elaboration].compact.join(' ')
      html.scan(/<icon=type([A-Z]+)/).flatten.map(&:downcase).uniq.each { |t| counts[t] += 1 }
    end
    return '' if counts.empty?

    path = scripts_dir ? File.join(scripts_dir, 'Reborn', 'typetext.rb') : nil
    src = path && File.exist?(path) ? File.read(path) : ''
    order = src.scan(/^  :([A-Z]+) =>/).flatten.map(&:downcase)

    chips = counts.keys.sort_by { |t| [order.index(t) || 99, t] }.map { |t|
      label = t == 'qmarks' ? '???' : JaNames.tr('types', t.capitalize)
      cls = t == 'qmarks' ? 'qmarks' : t
      %(<button type="button" class="ref-chip type-badge type-#{cls}" data-value="#{t}">) +
        %(#{escape(label)}<span>#{counts[t]}</span></button>)
    }.join

    ja = JaNames.enabled?
    <<~BAR
      <div class="ref-filter fn-filter" hidden>
        <div class="ref-filter-line">
          <input type="search" id="fn-q" class="ref-search" autocomplete="off"
                 placeholder="#{ja ? 'わざ名・とくせい名・フィールド名で絞る' : 'Filter by move, ability or field'}">
          <span class="ref-count" role="status" aria-live="polite"></span>
        </div>
        <div class="ref-filter-line ref-chips" data-group="types">
          <span class="ref-chip-label">#{ja ? 'タイプ' : 'Type'}</span>#{chips}
        </div>
        <div class="ref-filter-line">
          <button type="button" class="ref-reset">#{ja ? '条件を外す' : 'Clear'}</button>
        </div>
      </div>
    BAR
  end

  def build_page(game, scripts_dir)
    notes = load_notes(scripts_dir)
    return nil if notes.empty?

    table = names(scripts_dir)
    grouped = notes.group_by(&:fieldeffect)
    fields = note_keys(scripts_dir)

    jump = fields.map { |k|
      %(<li><a href="##{anchor(k)}">#{escape(display_name(k, table))}<span>#{grouped[k].size}</span></a></li>)
    }.join("\n  ")

    sections = fields.map do |k|
      list = grouped[k]
      lead = ''
      # 先頭の1行はフィールドが張られたときに出る台詞で、効果ではない。
      # 37/38 のフィールドが持っており、他の行がこの体裁を取ることは無い。
      if list.first.text =~ FLAVOR
        lead = %(<p class="fn-flavor">#{render(tr(list.first.text), scripts_dir, k)}</p>\n\n)
        list = list[1..]
      end
      items = list.map { |n| note_html(n, scripts_dir) }.join("\n  ")
      <<~SECTION
        ## #{display_name(k, table)} {##{anchor(k)}}

        #{lead}<ul class="field-notes">
          #{items}
        </ul>

        #{usage_html(k, game)}
      SECTION
    end

    title = JaNames.enabled? ? 'フィールド効果' : 'Field Effects'
    intro =
      if JaNames.enabled?
        "ゲーム内のポケギアにある「フィールドノート」を、そのまま読める形にしたものです。" \
        "フィールド #{fields.length}種 / #{notes.length}行。" \
        "攻略本文の戦闘に書いてある「フィールド」の名前から、それぞれの節へ直接飛べます。" \
        "下の欄で、わざ名・とくせい名・タイプから横断して絞り込めます" \
        "（「こおり」でこおり技に効くフィールドだけを並べる、など）。/ キーで入力欄に移れます。" \
        "当たった行には印を付けますが、フィールドは効果の組み合わせで判断するものなので、" \
        "残った効果もそのまま並べています。"
      else
        "The in-game Field Notes app, laid out as one page. " \
        "#{fields.length} fields / #{notes.length} lines. " \
        "Use the box below to filter across every field by move, ability or type. Press / to jump to it. " \
        "Matching lines are marked, but every effect of a matching field is kept on screen - " \
        "a field is judged by the combination, not by one line."
      end
    legend =
      if JaNames.enabled?
        '矢印は効果の向きを表します。<span class="fn-icon fn-up">↑</span> 上がる、' \
        '<span class="fn-icon fn-down">↓</span> 下がる、<span class="fn-icon fn-change">→</span> 変わる、' \
        '<span class="fn-icon fn-plus">＋</span> 加わる。' \
        '薄い字の行は、その1行の続き（対象になるわざやとくせいの一覧など）です。'
      else
        '<span class="fn-icon fn-up">↑</span> up, <span class="fn-icon fn-down">↓</span> down, ' \
        '<span class="fn-icon fn-change">→</span> becomes, <span class="fn-icon fn-plus">＋</span> gains. ' \
        'Dimmed lines continue the line above them.'
      end

    <<~PAGE
      ---
      title: #{title}
      permalink: /#{game}/fields/
      ---

      <p id="title-text">#{title}</p>

      <p class="ref-back"><a href="/#{game}/">#{JaNames.ui('Back to contents')}</a></p>

      #{intro}

      #{legend}
      {: .fn-legend}

      #{filter_html(notes, scripts_dir)}

      <nav class="affinity-jump fn-jump">
        <ul>
        #{jump}
        </ul>
      </nav>

      #{sections.join("\n")}
    PAGE
  end

  # フィールドが張られたときの台詞。<c=orange> で括った鉤括弧で始まる。
  FLAVOR = /\A<c=orange>["\u201C\u300C]/.freeze

  # このフィールドで戦う場面。戦闘表からこちらへは繋がっているが、
  # 逆向きが無いと対策を読んだあと本文に戻れない。
  def usage_html(key, game)
    places = FieldUsage.for(key)
    return '' if places.empty?

    links = places.map { |ctx|
      chapter = ctx[:chapter].to_s.sub(/[:：].*\z/, '').strip
      label = ctx[:section] == ctx[:chapter] ? chapter : "#{chapter} / #{ctx[:section]}"
      %(<li><a href="#{ctx[:href]}">#{escape(label)}</a></li>)
    }.join

    <<~USE.strip
      <div class="fn-usage">
        <span class="fn-usage-label">#{JaNames.ui('Battles on this field')}</span>
        <ul>#{links}</ul>
      </div>
    USE
  end

  # 表示名。屋内フィールドだけ fieldtext.rb 側に名前が無い。
  def display_name(key, table)
    raw = table[key.to_s].to_s
    return JaNames.enabled? ? '屋内' : 'Indoor' if raw.strip.empty?

    JaNames.field(raw)
  end
end
