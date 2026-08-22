# frozen_string_literal: true

require_relative 'ja_names'
require_relative 'doc_context'
require 'set'

# 出現ポケモンの逆引き。
#
# 攻略本文にある出現表 232個は「この場所に何が出るか」しか答えられない。
# 読者が実際に知りたいのは逆で、「この種族はどこで捕まえられるか」のほう。
#
# 表を作り直すのではなく、EncounterGetter が表を組む最中に1行ずつ受け取る。
# 画面に出るものと同じ数字・同じ表記になり、二重に解釈する余地が無い。
#
# 対象は攻略本文が扱うマップだけ (実測 205個)。ゲームデータには 403個あるが、
# 205個で 585種のうち 581種を拾えるうえ、すべての行から本文へ戻せる。
module EncounterIndex
  module_function

  RATE_LABELS = {
    LandMorning: 'morning', LandDay: 'day', LandNight: 'night',
    OldRod: 'oldrod', GoodRod: 'goodrod', SuperRod: 'superrod'
  }.freeze

  def entries
    @entries ||= []
  end

  def reset!
    @entries = []
    @species_keys = nil
  end

  def record(species:, species_key:, dexnum:, icon:, types:, held:, map_label:, group:, levels:, rates:)
    entries << {
      species: species,
      species_key: species_key,
      dexnum: dexnum.to_i,
      icon: icon,
      types: types,
      held: held,
      map_label: map_label,
      group: group,
      levels: levels,
      rates: rates,
      context: DocContext.current
    }
  end

  # 種族ごとにまとめる。並びは図鑑番号順。
  # 出現場所ページに行があるか。付録の持ち物の表から、その種族の行へ
  # リンクしてよいかの判定に使う。付録は章の最後に処理されるので、この
  # 時点では全章分が集まっている。
  def species_keys
    @species_keys ||= entries.map { |e| e[:species_key].to_s }.to_set
  end

  def has_species?(key)
    species_keys.include?(key.to_s)
  end

  # 種族ごとにまとめる。並びは図鑑番号順。
  #
  # 表示名だけでまとめるとニドラン♀と♂が1行に混ざる。ゲームのデータは
  # どちらも "Nidoran" で、図鑑番号だけが違う (29 と 32)。内部シンボルも
  # 鍵にして分ける。姿違い (アローラのすがた など) は表示名が違うので、
  # これでも分かれたままになる。
  def by_species
    grouped = entries.group_by { |e| [e[:species], e[:species_key]] }
    grouped.map { |(name, _key), list|
      { species: name, species_key: list.first[:species_key],
        dexnum: list.first[:dexnum], icon: list.first[:icon],
        types: list.first[:types], held: list.first[:held], places: dedupe(list) }
    }.sort_by { |s| [s[:dexnum], s[:species]] }
  end

  # 同じ場所・同じ出現方法の重複を落とす。1つのマップを複数の !enc() が
  # 別々の観点で出していることがあるため。
  def dedupe(list)
    seen = {}
    list.each do |e|
      key = [e[:map_label], e[:group], e.dig(:context, :href)]
      seen[key] ||= e
    end
    seen.values
  end
end
