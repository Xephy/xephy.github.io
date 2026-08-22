# frozen_string_literal: true

require_relative 'doc_context'

# 技教え人で教われるわざ。
#
# 本文の表は「この教え人が何を教えるか」しか答えられない。読者が知りたい
# のは逆で「このわざはどこで教われるか」「今どこまでで何が教われるか」。
#
# 実測で 教え人23人 / わざ78種 / のべ82件。4種は2箇所以上で教われる。
module TutorIndex
  module_function

  def entries
    @entries ||= []
  end

  def reset!
    @entries = []
  end

  def record(move:, tutor:, price:)
    entries << { move: move, tutor: tutor, price: price, context: DocContext.current }
  end

  # わざごとにまとめる。並びは本文に出てくる順 = 早く教われる順。
  def by_move
    order = []
    grouped = {}
    entries.each do |e|
      unless grouped.key?(e[:move])
        grouped[e[:move]] = []
        order << e[:move]
      end
      grouped[e[:move]] << e
    end
    order.map { |m| { move: m, tutors: grouped[m] } }
  end
end
