# frozen_string_literal: true

require_relative 'ja_names'
require 'cgi'
require 'set'
require_relative 'shop_index'

# 進化条件の一覧。
#
# リボーンの進化条件はゲームのデータにしかなく、どこにも書かれていなかった。
# 実測で 394件。方法は28種類あり、通信交換 (10) や交換 + どうぐ (16) の
# ように、1人では満たせないものも残っている。
#
# 条件の読み方は Scripts/Evolution.rb の checkEvoConditions に合わせた。
# なつき度は 220以上、Affection は「なつき度220以上 + そのタイプのわざを
# 覚えている」、BadInfluence は「手持ちにあくタイプがいる」。
module EvolutionIndex
  module_function

  # マップ集合で判定するもの (SystemConstants.rb)。
  MAP_SETS = {
    CRABRAWLER: 'Crabominable',
    MAGNETON: 'Magnetic', NOSEPASS: 'Magnetic', CHARJABUG: 'Magnetic'
  }.freeze

  LEVEL_SUFFIX = {
    LevelDay: '昼', LevelNight: '夜', LevelMale: '♂', LevelFemale: '♀',
    LevelRain: '雨のとき'
  }.freeze

  def collect(pokemon_hash)
    rows = []
    pokemon_hash.each do |species, forms|
      # 姿違いの枝には :dexnum が無いことがある。並べ替えが 0 に潰れるので
      # 基本形の番号を使う。
      base = forms.keys.find { |k| k.is_a?(String) }
      dexnum = base ? forms[base][:dexnum].to_i : 0

      forms.each do |form_key, data|
        next unless data.is_a?(Hash)

        (data[:evolutions] || []).each do |evo|
          rows << { from: species, form: form_key, to: evo[:species],
                    method: evo[:method], parameter: evo[:parameter], dexnum: dexnum }
        end
      end
    end
    rows.sort_by { |r| [r[:dexnum], r[:from].to_s, r[:to].to_s] }
  end

  # 条件を日本語の一文にする。読めない方法が来たら気づけるように警告する。
  #
  # map_sets は MonData.map_sets の返り値。渡さないと、マップ集合で判定する
  # 4件が「特定の場所でレベルアップ」のままになる。
  def describe(row, item_hash, move_hash, pokemon_hash, map_hash, map_sets = nil)
    m = row[:method]
    p = row[:parameter]

    case m
    when :Level, :Ninjask then "Lv.#{p}"
    when :LevelDay, :LevelNight, :LevelMale, :LevelFemale, :LevelRain
      "Lv.#{p}（#{LEVEL_SUFFIX[m]}）"
    when :AttackGreater then "Lv.#{p}（こうげき > ぼうぎょ）"
    when :DefenseGreater then "Lv.#{p}（ぼうぎょ > こうげき）"
    when :AtkDefEqual then "Lv.#{p}（こうげき = ぼうぎょ）"
    when :Silcoon, :Cascoon then "Lv.#{p}（どちらになるかは個体ごとに決まっている）"
    when :Shedinja then "Lv.#{p}（手持ちに空きとモンスターボールが要る）"
    when :BadInfluence then "Lv.#{p}（手持ちにあくタイプがいる）"
    when :Item then "#{item_name(p, item_hash)}を使う"
    when :ItemMale then "#{item_name(p, item_hash)}を使う（♂）"
    when :ItemFemale then "#{item_name(p, item_hash)}を使う（♀）"
    when :Trade then trade_text(row, item_hash, pokemon_hash)
    when :TradeItem then "#{item_name(p, item_hash)}を持たせて#{link_stone(item_hash)}を使う"
    when :DayHoldItem then "#{item_name(p, item_hash)}を持たせてレベルアップ（昼）"
    when :NightHoldItem then "#{item_name(p, item_hash)}を持たせてレベルアップ（夜）"
    when :Happiness then 'なつき度220以上でレベルアップ'
    when :HappinessDay then 'なつき度220以上でレベルアップ（昼）'
    when :HappinessNight then 'なつき度220以上でレベルアップ（夜）'
    when :Affection then "なつき度220以上で、#{type_name(p)}のわざを覚えた状態でレベルアップ"
    when :HasMove then "#{move_name(p, move_hash)}を覚えた状態でレベルアップ"
    when :HasInParty then "手持ちに#{species_name(p, pokemon_hash)}がいる状態でレベルアップ"
    when :Location then location_text(row, map_hash, map_sets)
    else
      warn "未対応の進化方法: #{m} (#{row[:from]} -> #{row[:to]})"
      m.to_s
    end
  end

  # リンクストーンで進化させるとき、手持ちに相方が要るもの。
  # Trading.rb:254-255。交換で進化させる場合はこの条件が付かない。
  TRADE_PARTNER = { SHELMET: :KARRABLAST, KARRABLAST: :SHELMET }.freeze

  # 1人用のゲームなので通信交換の相手がいない。Trading.rb の
  # pbTradeCheckEvolution が交換の相手として :LINKSTONE を受け取るので、
  # リンクストーンを使えば交換したことになる。読む人が実際に取れる手は
  # こちらなので、条件はリンクストーンの側で書く。
  def link_stone(item_hash)
    item_name(:LINKSTONE, item_hash)
  end

  def trade_text(row, item_hash, pokemon_hash)
    partner = TRADE_PARTNER[row[:from]]
    base = "#{link_stone(item_hash)}を使う"
    return base unless partner

    "手持ちに#{species_name(partner, pokemon_hash)}がいる状態で#{base}"
  end

  # マップ名から階層の表記を落とす。ゲームは「アメトリン山2階」のように
  # 1フロア1マップで持っているので、そのまま並べると同じ山が何度も出る。
  FLOOR = /(地下)?\d+階.*\z/

  # 集合で判定するもののうち、階層を落としても名前が何種類も残るものだけ、
  # 読める言い方をここに書く。expect は書いた時点でデータから出した名前で、
  # ゲーム側が変わったら warn で気づけるようにするための控え。
  SET_LABEL = {
    'Crabominable' => {
      label: 'アメトリンシティ周辺・アメトリン山・セレスティナイン山',
      expect: %w[アメトリン山 セレスティナイン山 アメトリンシティ
                 アメトリンポケモンセンター アメトリンショップ アメトリンどうくつ]
    }
  }.freeze

  def location_text(row, map_hash, map_sets = nil)
    set = MAP_SETS[row[:from]]
    return "#{escape(map_set_name(set, map_sets, map_hash))}でレベルアップ" if set

    name = map_hash[row[:parameter].to_i]
    name ? "#{escape(name)}でレベルアップ" : '特定の場所でレベルアップ'
  end

  # 集合に入っているマップの名前を、読める1つの言い方にまとめる。
  def map_set_name(set, map_sets, map_hash)
    ids = map_sets && map_sets[set]
    return '特定の場所' if ids.nil? || ids.empty?

    names = ids.filter_map { |id| map_hash[id] }.map { |n| n.sub(FLOOR, '') }.uniq
    return '特定の場所' if names.empty?
    return names[0] if names.size == 1

    entry = SET_LABEL[set]
    unless entry
      warn "進化の場所をまとめる書き方が無い: #{set} (#{names.join('・')})"
      return names.join('・')
    end
    if names.sort != entry[:expect].sort
      warn "進化の場所が変わっている: #{set} 期待 #{entry[:expect].join('・')} / 実際 #{names.join('・')}"
    end
    entry[:label]
  end

  # 大まかな分け方。絞り込みの札に使う。
  def group(method)
    case method
    when :Trade, :TradeItem then 'trade'
    when :Item, :ItemMale, :ItemFemale then 'item'
    when :Happiness, :HappinessDay, :HappinessNight, :Affection then 'happiness'
    when :Location then 'location'
    when :Level, :LevelDay, :LevelNight, :LevelMale, :LevelFemale, :LevelRain,
         :Ninjask, :AttackGreater, :DefenseGreater, :AtkDefEqual, :Silcoon, :Cascoon
      'level'
    else 'other'
    end
  end

  # どうぐの名前。店で扱っているものは、店の索引へ繋ぐ。実測では進化に
  # 使う27種すべてがどこかの店で買える。
  def item_name(sym, item_hash)
    name = item_hash[sym] ? item_hash[sym][:name] : sym.to_s
    return escape(name) unless shop_items.include?(name)

    %(<a href="/reborn/shops/?q=#{CGI.escape(name)}">#{escape(name)}</a>)
  end

  def shop_items
    @shop_items ||= ShopIndex.entries.map { |e| e[:item] }.to_set
  end

  def escape(text)
    text.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;')
  end

  def move_name(sym, move_hash)
    escape(move_hash[sym] ? move_hash[sym][:name] : sym.to_s)
  end

  def species_name(sym, pokemon_hash)
    forms = pokemon_hash[sym]
    return sym.to_s unless forms

    key = forms.keys.find { |k| k.is_a?(String) }
    escape(key ? forms[key][:name] : sym.to_s)
  end

  def type_name(sym)
    escape(sym == :QMARKS ? '???' : JaNames.tr('types', sym.to_s.capitalize))
  end
end
