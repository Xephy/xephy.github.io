# frozen_string_literal: true

require_relative 'doc_context'

# バッジを手に入れる場面。レベル上限の表に添えるために集める。
#
# ジムの数は18。順番はゲームのデータには無いので、本文に出てくる順で取る。
# 節の名前がそのままバッジ名になっている場合と、本文中に *まゆバッジ* の
# ように書かれている場合があるので、両方を見る (見出しだけでは16本、
# 斜体だけでは14本しか集まらない)。
#
# 付録は章の最後に処理されるので、!levelcaps() が呼ばれる時点では
# 本編19章ぶんが集まっている。
module BadgeIndex
  module_function

  NAME = /([ぁ-んァ-ヶー]+バッジ)/.freeze
  # 総称なので個別のバッジではない。
  GENERIC = ['ジムバッジ'].freeze

  def badges
    @badges ||= []
  end

  def reset!
    @badges = []
    @seen = {}
  end

  def record(name)
    @seen ||= {}
    return if GENERIC.include?(name) || @seen[name]

    @seen[name] = true
    badges << { name: name, context: DocContext.current }
  end

  # 見出し1行、または本文1行から拾う。
  def scan_heading(text)
    record(Regexp.last_match(1)) if text.to_s.strip =~ /\A#{NAME}\z/
  end

  def scan_line(line)
    line.to_s.scan(/\*#{NAME}\*/) { |m| record(m[0]) }
  end
end
