# frozen_string_literal: true

require 'set'
require_relative 'ja_names'

# ポケモン1種ぶんの情報を、ゲームのデータから引き直すための道具箱。
#
# 表示は MonPage が行う。ここは「何を覚えるか」「何に弱いか」「どう進化するか」
# のような、間違えると嘘になる判定だけを持つ。判定はすべてゲームのコードに
# 合わせてあり、攻略本文の書き方には依存しない。
module MonData
  module_function

  # --- ゲームの定数 ---------------------------------------------------------

  # 技教え人が扱うわざ。ゲームでは SystemConstants.rb の TUTORMOVES に
  # 直接書かれていて、データとしては取り出せないので読み取る。
  def tutor_moves(scripts_dir)
    @tutor_moves ||= {}
    @tutor_moves[scripts_dir] ||= begin
      src = File.read(File.join(scripts_dir, 'Reborn', 'SystemConstants.rb'))
      body = src[/TUTORMOVES = \[(.*?)\n\]/m, 1].to_s
      body.scan(/:(\w+)/).flatten.map(&:to_sym).uniq
    end
  end

  # ほぼ全種が覚えるわざ。Pokemon.rb の SpeciesCompatible? が、
  # 種族ごとの compatiblemoves を見る前にこれを通す。
  def universal_moves(scripts_dir)
    @universal_moves ||= {}
    @universal_moves[scripts_dir] ||= begin
      src = File.read(File.join(scripts_dir, 'PBStuff.rb'))
      src[/UNIVERSALTMS = \[(.*?)\]/m, 1].to_s.scan(/:(\w+)/).flatten.map(&:to_sym)
    end
  end

  # わざマシン・ひでんマシンが教えるわざ。
  def machine_moves(item_hash)
    @machine_moves ||= {}
    @machine_moves[item_hash.object_id] ||= item_hash.filter_map { |_, i| i[:tm] }.uniq.to_set
  end

  def reset!
    @tutor_moves = @universal_moves = @machine_moves = nil
  end

  # --- 種族と姿 -------------------------------------------------------------

  def slug(species)
    species.to_s.downcase
  end

  # 姿の並び。:OnCreation のような枝は姿ではないので外す。
  def form_keys(forms)
    forms.keys.select { |k| k.is_a?(String) }
  end

  # 姿ごとの値。その姿に無ければ基本形から借りる。
  # DataObjects.rb が compatiblemoves などで同じ順に解決している。
  def attr_of(forms, form_key, key)
    base_key = form_keys(forms).first
    value = forms[form_key] ? forms[form_key][key] : nil
    value.nil? ? forms[base_key][key] : value
  end

  def base_data(forms)
    forms[form_keys(forms).first]
  end

  # 「メガフォルム」のような姿の名前。基本形は姿の区別が要らない。
  def form_label(form_key)
    return JaNames.ui('Normal Form') if form_key.to_s.start_with?('Normal')

    JaNames.tr('form_names', form_key).to_s.sub(' Form', '').sub(' Forme', '')
  end

  # --- わざを覚えられるか ---------------------------------------------------

  # Pokemon.rb の SpeciesCompatible? をそのままなぞる。順番に意味がある。
  #
  # moveexceptions が未定義の姿は「基本形のもの」→「無ければ UNIVERSALTMS」の
  # 順で埋まる (DataObjects.rb)。既定値が UNIVERSALTMS なので、素直に
  # 空配列を当てると、全種共通のわざを覚えられないポケモンを見落とす。
  def learnable?(species, forms, form_key, move, item_hash, scripts_dir)
    universal = universal_moves(scripts_dir)
    exceptions = attr_of(forms, form_key, :moveexceptions) || universal
    return false if exceptions.include?(move)
    return true if species == :MEW
    return true if universal.include?(move)

    compat = attr_of(forms, form_key, :compatiblemoves) || []
    if compat.include?(move) &&
       (machine_moves(item_hash).include?(move) || tutor_moves(scripts_dir).include?(move))
      return true
    end
    return true if (attr_of(forms, form_key, :RelearnerMoves) || []).include?(move)
    return true if (attr_of(forms, form_key, :Moveset) || []).any? { |_, m| m == move }

    (attr_of(forms, form_key, :EggMoves) || []).include?(move)
  end

  # --- タイプ相性 -----------------------------------------------------------

  # 防御側から見た倍率。typetext.rb は「このタイプは何に弱いか」を持つので、
  # 攻撃タイプごとに2つのタイプぶんを掛け合わせる。
  def matchups(type_hash, type1, type2)
    type_hash.keys.to_h do |attacker|
      mult = [type1, type2].compact.reduce(1.0) do |acc, def_type|
        d = type_hash[def_type]
        next acc unless d
        next acc * 0 if (d[:immunities] || []).include?(attacker)
        next acc * 2 if (d[:weaknesses] || []).include?(attacker)
        next acc * 0.5 if (d[:resistances] || []).include?(attacker)

        acc
      end
      [attacker, mult]
    end
  end

  # --- 進化 -----------------------------------------------------------------

  # 進化の枝。姿によって進化先が違う (アローラのニャースは なつき度) ので、
  # いま見ている種族だけはその姿の枝を使い、ほかは基本形の枝を使う。
  def evo_children(pokemon_hash, species, form_key = nil)
    forms = pokemon_hash[species]
    return [] unless forms

    key = form_key && forms.key?(form_key) ? form_key : form_keys(forms).first
    (attr_of(forms, key, :evolutions) || []).map do |evo|
      { from: species, form: key, to: evo[:species],
        method: evo[:method], parameter: evo[:parameter] }
    end
  end

  # 系統の根まで遡る。2進化のポケモンを途中から見ても全体が見えるようにする。
  def evo_root(pokemon_hash, species, form_key)
    current = species
    key = form_key
    4.times do
      forms = pokemon_hash[current]
      break unless forms

      k = forms.key?(key) ? key : form_keys(forms).first
      pre = attr_of(forms, k, :preevo)
      break unless pre && pokemon_hash[pre[:species]] && pre[:species] != current

      current = pre[:species]
      key = nil
    end
    current
  end

  # 根から葉までの道すじ。枝分かれ (イーブイ) は道すじの数だけ返す。
  # 要素は { species: } と { child: 進化の枝 } が交互に並ぶ。
  def evo_paths(pokemon_hash, node, self_species, self_form, depth = 0)
    children = depth > 3 ? [] : evo_children(pokemon_hash, node, node == self_species ? self_form : nil)
    return [[{ species: node }]] if children.empty?

    children.flat_map do |child|
      evo_paths(pokemon_hash, child[:to], self_species, self_form, depth + 1).map do |rest|
        [{ species: node }, { child: child }] + rest
      end
    end
  end

  # --- 数値の言い換え -------------------------------------------------------

  # 性別の比・経験値タイプ・たまごグループは、ui.yml の英語キーと衝突する
  # ものがある (たまごグループの Grass は、出現方法の「くさむら」と同じキー)。
  # 混ざると別の場所の訳を壊すので、ここだけ対訳を手元に持つ。
  #
  # 比の値は Pokemon.rb の gender が使う閾値そのまま (255分率)。
  GENDER_EN = {
    Genderless: 'Genderless', MaleZero: 'Always female', FemZero: 'Always male',
    FemEighth: 'M 87.5 / F 12.5', FemQuarter: 'M 75 / F 25', FemHalf: 'M 50 / F 50',
    MaleQuarter: 'M 25 / F 75', MaleEighth: 'M 12.5 / F 87.5'
  }.freeze
  GENDER_JA = {
    Genderless: '性別なし', MaleZero: '♀のみ', FemZero: '♂のみ',
    FemEighth: '♂ 87.5 / ♀ 12.5', FemQuarter: '♂ 75 / ♀ 25', FemHalf: '♂ 50 / ♀ 50',
    MaleQuarter: '♂ 25 / ♀ 75', MaleEighth: '♂ 12.5 / ♀ 87.5'
  }.freeze

  GROWTH_EN = { Fast: 'Fast', MediumFast: 'Medium Fast', MediumSlow: 'Medium Slow',
                Slow: 'Slow', Erratic: 'Erratic', Fluctuating: 'Fluctuating' }.freeze
  GROWTH_JA = { Fast: 'はやい', MediumFast: 'ふつう', MediumSlow: '少しおそい',
                Slow: 'おそい', Erratic: 'ふぞろい', Fluctuating: 'むら' }.freeze

  EGG_GROUP_EN = {
    Monster: 'Monster', Water1: 'Water 1', Water2: 'Water 2', Water3: 'Water 3',
    Bug: 'Bug', Flying: 'Flying', Field: 'Field', Fairy: 'Fairy', Grass: 'Grass',
    HumanLike: 'Human-Like', Mineral: 'Mineral', Amorphous: 'Amorphous',
    Dragon: 'Dragon', Undiscovered: 'Undiscovered'
  }.freeze
  EGG_GROUP_JA = {
    Monster: 'かいじゅう', Water1: 'すいちゅう1', Water2: 'すいちゅう2', Water3: 'すいちゅう3',
    Bug: 'むし', Flying: 'ひこう', Field: 'りくじょう', Fairy: 'ようせい', Grass: 'しょくぶつ',
    HumanLike: 'ひとがた', Mineral: 'こうぶつ', Amorphous: 'ふていけい',
    Dragon: 'ドラゴン', Undiscovered: 'タマゴみはっけん'
  }.freeze

  # 能力値とわざの分類は、既に ui.yml にあるものをそのまま使う。
  # 攻略本文の表と同じ言い方になる。
  # ゲーム内のタイプの並び。絞り込みの札を並べるのに使う。辞書順だと
  # 「ノーマル・ほのお・みず…」の見慣れた並びから外れる。
  TYPE_ORDER = %w[normal fighting flying poison ground rock bug ghost steel
                  fire water grass electric psychic ice dragon dark fairy shadow].freeze

  STATS = %w[HP Atk Def SpA SpD Spe].freeze
  CATEGORY = { physical: 'physical', special: 'special', status: 'status' }.freeze

  # 野生が持っている道具の確率。付録の「野生ポケモンの持ち物」と同じ値。
  WILD_ITEM_RATES = { WildItemCommon: '50%', WildItemUncommon: '5%', WildItemRare: '1%' }.freeze

  def gender_label(sym)
    (JaNames.enabled? ? GENDER_JA[sym] : GENDER_EN[sym]) || sym.to_s
  end

  def growth_label(sym)
    (JaNames.enabled? ? GROWTH_JA[sym] : GROWTH_EN[sym]) || sym.to_s
  end

  def egg_group_label(sym)
    (JaNames.enabled? ? EGG_GROUP_JA[sym] : EGG_GROUP_EN[sym]) || sym.to_s
  end

  def stat_label(index)
    JaNames.ui(STATS[index])
  end

  def category_label(sym)
    JaNames.ui(CATEGORY[sym] || sym.to_s)
  end
end
