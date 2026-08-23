# frozen_string_literal: true

require_relative 'doc_context'

# トレーナーの手持ちの逆引き。「このポケモンは誰が使うか」。
#
# 本文の戦闘表は「このトレーナーが何を使うか」しか答えられない。ポケモン
# 個別ページはその逆を必要とする。表を組み直すのではなく、TrainerGetter が
# 表を組む最中に1体ずつ受け取るので、画面に出るものと数が食い違わない。
#
# 先の展開が見えてしまう情報なので、個別ページでは既定で畳んで出す。
module TrainerIndex
  module_function

  def entries
    @entries ||= []
  end

  def reset!
    @entries = []
  end

  def record(species:, form:, level:, trainer:)
    return unless species

    entries << { species: species, form: form.to_i, level: level,
                 trainer: trainer.to_s, context: DocContext.current }
  end

  # 種族ごとにまとめる。同じトレーナーが同じ節で複数体使うことがあるので、
  # トレーナーと節でまとめ、体数とレベルを添える。並びは本文に出てくる順。
  def by_species
    grouped = Hash.new { |h, k| h[k] = [] }
    entries.each { |e| grouped[e[:species]] << e }

    grouped.transform_values do |list|
      order = []
      rows = {}
      list.each do |e|
        key = [e[:trainer], e.dig(:context, :href)]
        unless rows.key?(key)
          rows[key] = { trainer: e[:trainer], context: e[:context], levels: [], count: 0 }
          order << key
        end
        rows[key][:count] += 1
        rows[key][:levels] << e[:level].to_i if e[:level]
      end
      order.map { |k| rows[k].merge(levels: rows[k][:levels].uniq.sort) }
    end
  end
end
