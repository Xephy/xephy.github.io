# frozen_string_literal: true

require_relative 'doc_context'

# どのフィールドが本文のどこで使われているか。
#
# 戦闘表からフィールド効果ページへは繋がったが、逆向きが無かった。
# 「このフィールドで戦うのはどこか」が分かると、対策を立てた流れのまま
# 本文へ戻れる。実測で 695戦闘 / 節は1フィールドあたり中央値7・最大18。
module FieldUsage
  module_function

  def sections
    @sections ||= Hash.new { |h, k| h[k] = {} }
  end

  def reset!
    @sections = Hash.new { |h, k| h[k] = {} }
  end

  def record(key)
    ctx = DocContext.current
    return unless key && ctx && ctx[:href]

    # 同じ節で何度も戦うことがあるので、節ごとに1つにまとめる。
    sections[key][ctx[:href]] ||= ctx
  end

  def for(key)
    sections[key].values
  end
end
