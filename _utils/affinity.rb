# frozen_string_literal: true

require_relative 'ja_names'

# 「好感度の選択肢」ブロックを読みやすい形に組み直す。
#
# 生の原稿では、ラベル1行と項目リストの組が延々と続く。実測すると 227組の
# うち 107組が隣り合っており、1項目しか持たないラベルが縦に積み重なって
# 間延びしていた。隣接する組はひとまとめにする。
#
# 生 HTML で包まないのは、項目に *いやしのすず* のような markdown 装飾が
# 4件あり、raw HTML ブロックの中では kramdown が処理を止めてしまうため。
# 代わりにブロック IAL ({: .class}) で class だけ付ける。増減値は行内 HTML
# なので markdown の処理を妨げない。
module Affinity
  module_function

  LABELS = ['**Relationship Point Choices**:', '**好感度の選択肢**:'].freeze

  # 行末の半角括弧。"(+1 ハーディ)" "(-1 ヴィクトリア, -1 アークライト)"
  # "(増減なし)" などを拾う。全角括弧で書かれた注記 (説明文であって増減では
  # ないもの) は意図的に対象外。
  DELTA = /\s*\(([^()]+)\)\s*\z/.freeze

  def apply(content)
    lines = content.to_s.split("\n", -1)
    out = []
    i = 0

    while i < lines.length
      unless label?(lines[i])
        out << lines[i]
        i += 1
        next
      end

      items = []
      i = collect(lines, i, items)
      out.concat(render(items))
    end

    out.join("\n")
  end

  # 連続する「ラベル + 項目」の組をすべて読み取り、次の位置を返す。
  def collect(lines, i, items)
    while i < lines.length && label?(lines[i])
      i += 1
      i += 1 while i < lines.length && lines[i].strip.empty?
      while i < lines.length && lines[i].start_with?('- ')
        items << lines[i][2..]
        i += 1
      end
      # 次の組との間の空行を読み飛ばす。組でなければ位置は戻す。
      j = i
      j += 1 while j < lines.length && lines[j].strip.empty?
      break unless j < lines.length && label?(lines[j])

      i = j
    end
    i
  end

  def render(items)
    ['<!-- 好感度 -->',
     "**#{JaNames.ui('Relationship Point Choices')}**",
     '{: .affinity-label}',
     '',
     *items.map { |it| "- #{decorate(it)}" },
     '{: .affinity-list}',
     '']
  end

  # 行末の増減値に印を付ける。上げ / 下げ / 両方 / 増減なしで色を分ける。
  def decorate(item)
    m = item.match(DELTA)
    return item unless m

    inner = m[1]
    up = inner.include?('+')
    down = inner.include?('-') || inner.include?('−')
    tone = if up && down then 'is-mixed'
           elsif up then 'is-up'
           elsif down then 'is-down'
           else 'is-none'
           end
    %(#{item.sub(DELTA, '')} <span class="affinity-delta #{tone}">#{inner}</span>)
  end

  def label?(line)
    LABELS.include?(line.to_s.strip)
  end
end
