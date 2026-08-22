# frozen_string_literal: true

require_relative 'ja_names'

# わざマシン・ひでんマシンの一覧。
#
# 「わざマシン57はどこで手に入るのか」「今持っているマシンは何のわざか」を
# 引く場所が無かった。本文には番号が散らばっているだけで、番号とわざの
# 対応はゲームのデータにしかない。
#
# 実測で 109本 (わざマシン100 + ひでんマシン9)。本文で言及があるのは103本。
#
# 番号は表示名から取る。内部キーは TM70 が「ひでんマシン8」だったりして
# あてにならない (ひでんマシン7/8 の内部キーは TM94/TM70、逆に本物の
# わざマシン70/94 は TM702/TM942)。表示名は109本すべて重複が無い。
module MachineIndex
  module_function

  NUMBER = /(\d+)\s*\z/.freeze

  def build(item_hash, move_hash)
    rows = item_hash.filter_map do |_key, item|
      move_sym = item[:tm]
      next unless move_sym

      move = move_hash[move_sym]
      next unless move

      label = item[:name].to_s
      { label: label, move: move, kind: label.start_with?('ひでん') ? 1 : 0,
        number: label[NUMBER, 1].to_i }
    end
    rows.sort_by { |r| [r[:kind], r[:number]] }
  end

  # 本文のどの節でこのマシンに触れているか。
  #
  # 「わざマシン10」が「わざマシン100」の中に当たらないよう、番号の直後が
  # 数字でないことを確かめる。
  def locations(chapters, game, labels)
    found = Hash.new { |h, k| h[k] = {} }
    patterns = labels.to_h { |l| [l, /#{Regexp.escape(l)}(?!\d)/] }

    chapters.each do |chapter|
      base = "/#{game}/#{chapter[:slug]}/"
      # 最初の ## より前に出てくる言及がある (ひでんマシン4 など)。節が
      # 始まる前は章そのものを指しておく。
      section = { text: chapter[:title].to_s.sub(/[:：].*\z/, '').strip,
                  href: base, chapter: chapter[:title] }

      chapter[:content].each_line do |line|
        m = line.chomp.match(/\A(\#{2,3})[ \t]+(.+?)[ \t]*\{\#([^}]+)\}[ \t]*\z/)
        if m
          section = { text: m[2].strip, href: "#{base}##{m[3]}", chapter: chapter[:title] }
          next
        end
        next unless section

        patterns.each do |label, re|
          found[label][section[:href]] ||= section if line =~ re
        end
      end
    end

    found
  end
end
