# frozen_string_literal: true

require 'set'
require_relative 'ja_names'

# わざから、それを覚えられるポケモンを引くための索引。
#
# 図鑑は「このポケモンは何を覚えるか」の向きでしか引けなかった。読者が
# 手を止めて調べるのは逆で「このわざは誰が覚えるのか」。手持ちを組むとき、
# 相手の弱点を突けるわざを誰に持たせるか、という引き方をする。
#
# 実測で わざ691本 / のべ 50,043組。1本あたりの中央値は25匹だが、
# みがわりのように 787匹が覚えるものもある。
#
# 総当たりで組むと 691 × 808 = 558,000回の判定になる。そうはせず、
# 個別ページを組んでいる最中に MonPage が結果を投げ込む。あちらは既に
# 姿ごとに覚えるわざを確定させているので、判定は1回も増えない。
# 表示が食い違わないという副産物もある。
module MoveIndex
  module_function

  # 覚え方。並びは表示順で、レベルが先。
  WAYS = %i[level machine tutor egg relearner shadow].freeze

  WAY_JA = { level: 'レベル', machine: 'わざマシン', tutor: '教え技',
             egg: 'タマゴ', relearner: '思い出し', shadow: 'シャドウ' }.freeze
  WAY_EN = { level: 'Level', machine: 'TM', tutor: 'Tutor',
             egg: 'Egg', relearner: 'Relearner', shadow: 'Shadow' }.freeze

  def entries
    @entries ||= {}
  end

  def reset!
    @entries = {}
  end

  # MonPage が姿ごとに呼ぶ。同じ組が姿の数だけ来るので、ここでまとめる。
  #
  # level だけは値を持つ。姿によって覚えるレベルが違うことがある
  # (アローラのすがた) ので、いちばん早いものを残す。
  def record(move:, species:, form_index:, way:, level: nil, machine: nil)
    return unless move

    slot = (entries[move] ||= {})[species] ||= { forms: Set.new, ways: {} }
    slot[:forms] << form_index

    if way == :level
      current = slot[:ways][:level]
      slot[:ways][:level] = level if current.nil? || (level && level < current)
    else
      slot[:ways][way] ||= true
    end
    slot[:machine] ||= machine if machine
  end

  # わざ1本ぶんの一覧。並びは図鑑番号順。
  def learners(move, dex_index)
    (entries[move] || {}).keys.sort_by { |species| dex_index[species] || 9999 }
  end

  def slot(move, species)
    (entries[move] || {})[species]
  end

  def count(move)
    (entries[move] || {}).size
  end

  # 覚え方の内訳。索引ページの「レベルで15匹・マシンで40匹」に使う。
  def way_counts(move)
    counts = Hash.new(0)
    (entries[move] || {}).each_value do |slot|
      slot[:ways].each_key { |way| counts[way] += 1 }
    end
    counts
  end

  def moves
    entries.keys
  end

  def way_label(way)
    (JaNames.enabled? ? WAY_JA[way] : WAY_EN[way]) || way.to_s
  end
end
