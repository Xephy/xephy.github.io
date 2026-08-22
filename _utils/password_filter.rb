# frozen_string_literal: true

require_relative 'ja_names'

# 付録の「パスワード全一覧」に絞り込みの操作子を差し込む。
#
# 215語が6つの分類に分かれて並んでいるだけで、目で追うしかなかった。
# 「レベル」で探せば hardcap / leveloffset / percentlevel / levelfloor が
# 一度に出る、という引き方ができるようにする。
#
# 一覧そのものは生の原稿に手で書かれているので、ここでは操作子だけを
# 差し込み、どの項目がどの分類かは表示後の DOM から JavaScript が読む。
module PasswordFilter
  module_function

  SECTION = '{#full-password-list}'
  HEADING = /^### (.+?) \{#([^}]+)\}$/.freeze
  ITEM = /^- \*\*[^*]+\*\*:/.freeze
  TABLE_ROW = '<tr data-pw='

  BULK = '{#bulk-passwords}'
  ITEM_HEAD = /^- \*\*([^*]+)\*\*:/.freeze

  def apply(content, game = 'reborn')
    text = link_bulk(content.to_s)
    at = text.index(SECTION)
    return text unless at

    chips = build_chips(text[at..])
    return text if chips.empty?

    # 見出しの次の段落 (読む前の注意書き) の後ろに置く。
    line_end = text.index("\n", at) or return text
    para_end = text.index("\n\n", line_end)
    return text unless para_end

    insert = "\n\n#{bar(chips)}"
    text[0...(para_end + 1)] + insert + text[(para_end + 1)..]
  end

  # まとめパスワードの中身を、各項目へのリンクにする。
  #
  # 「qol に何が入っているか」を見るたびに上へスクロールして名前を目で
  # 探すことになっていた。まとめ9件から のべ68件 の参照がある。
  #
  # 参照は別名で書かれていることがある (norolls は nodamageroll の別名)。
  # 別名から項目を引けるようにしてから差し替える。
  def link_bulk(text)
    at = text.index(SECTION) or return text
    bulk_at = text.index(BULK, at) or return text

    head = text[at...bulk_at]
    ids = {}
    head.each_line do |line|
      m = ITEM_HEAD.match(line) or next
      names = m[1].split('/').map(&:strip)
      slug = "pw-#{names.first}"
      names.each { |n| ids[n] ||= slug }
    end
    return text if ids.empty?

    head = head.gsub(ITEM_HEAD) do
      names = Regexp.last_match(1)
      %(- **<span id="pw-#{names.split('/').first.strip}">#{names}</span>**:)
    end

    # まとめの節だけを対象にする。次の見出しから先には触らない。
    rest = text[bulk_at..]
    stop = rest.index(/^\#{1,3} /, 1) || rest.length
    text[0...at] + head + link_members(rest[0...stop], ids) + rest[stop..].to_s
  end

  # 「- **qol**: hardcap, easyhms, ...」の右側だけを差し替える。
  def link_members(bulk, ids)
    bulk.gsub(/^(- \*\*[^*]+\*\*: )(.+)$/) do
      lead = Regexp.last_match(1)
      members = Regexp.last_match(2).split(',').map do |raw|
        name = raw.strip
        id = ids[name]
        id ? "[#{name}](##{id})" : name
      end
      lead + members.join(', ')
    end
  end

  # 分類ごとの見出しと件数。表で出しているフィールド指定のパスワードは
  # 箇条書きではないので、表の行も数える。
  def build_chips(section)
    heads = section.scan(HEADING)
    return [] if heads.empty?

    positions = heads.map { |title, id| [title, id, section.index("{##{id}}")] }
    positions.each_with_index.map do |(title, id, from), i|
      to = positions[i + 1] ? positions[i + 1][2] : section.length
      body = section[from...to]
      count = body.each_line.count { |l| l =~ ITEM } + body.scan(TABLE_ROW).length
      { id: id, label: title.sub(/のパスワード\z/, ''), count: count }
    end
  end

  def bar(chips)
    ja = JaNames.enabled?
    buttons = chips.map { |c|
      %(<button type="button" class="ref-chip pw-chip" data-value="#{c[:id]}">) +
        %(#{escape(c[:label])}<span>#{c[:count]}</span></button>)
    }.join

    <<~BAR.strip
      <div class="ref-filter pw-filter" hidden>
        <div class="ref-filter-line">
          <input type="search" id="pw-q" class="ref-search" autocomplete="off"
                 placeholder="#{ja ? 'パスワード名・効果で絞る' : 'Filter by password or effect'}">
          <span class="ref-count" role="status" aria-live="polite"></span>
        </div>
        <div class="ref-filter-line ref-chips" data-group="cats">
          <span class="ref-chip-label">#{ja ? '分類' : 'Group'}</span>#{buttons}
        </div>
        <div class="ref-filter-line">
          <button type="button" class="ref-reset">#{ja ? '条件を外す' : 'Clear'}</button>
        </div>
      </div>
    BAR
  end

  def escape(text)
    text.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;')
  end
end
