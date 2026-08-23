# frozen_string_literal: true

require_relative 'ja_names'

# わざの説明に書かれている「急所に当たりやすい」「能力を上げる」を、
# 具体的な数字に直すための道具。
#
# 説明文は本家の言い回しをそのまま訳したもので、程度が分からない。読者が
# 実際に知りたいのは「どのくらい当たるのか」「何段階上がるのか」なので、
# ゲームのデータとコードから拾って添える。
#
# 出どころは3つ:
#   1. movetext.rb  … 追加効果の確率 (:effect) と急所 (:highcrit)
#   2. Battle_Move.rb … 急所の倍率表 (ratios)
#   3. Battle_MoveEffects.rb … 能力変化の段階 (pbIncreaseStat の引数)
#
# 3 はコードを読むので、枝が複数あるもの (フィールドで値が変わるつるぎのまい
# など) は数字を出さない。1つに決まるものだけを載せる。
module MoveFacts
  module_function

  STAT_JA = {
    'ATTACK' => 'こうげき', 'DEFENSE' => 'ぼうぎょ', 'SPATK' => 'とくこう',
    'SPDEF' => 'とくぼう', 'SPEED' => 'すばやさ',
    'ACCURACY' => 'めいちゅう', 'EVASION' => 'かいひ'
  }.freeze

  STAT_EN = {
    'ATTACK' => 'Attack', 'DEFENSE' => 'Defense', 'SPATK' => 'Sp. Atk',
    'SPDEF' => 'Sp. Def', 'SPEED' => 'Speed',
    'ACCURACY' => 'accuracy', 'EVASION' => 'evasion'
  }.freeze

  # 能力変化を読み取る行。誰の・上げるか下げるか・どの能力・何段階。
  # 段階は数字で書かれていることも、変数で渡されることもある。
  # 能力は PBStats::ATTACK と直に書かれることも、繰り返しの変数で
  # 渡されることもある (からをやぶるは for stat in [...] で回している)。
  STAT_CALL = /(attacker|opponent)\.pb(Increase|Reduce)Stat\w*\(\s*(?:PBStats::)?(\w+),\s*(\w+)/.freeze
  STAT_LOOP = /\Afor\s+(\w+)\s+in\s+\[([^\]]+)\]/.freeze

  def data(scripts_dir)
    @data ||= {}
    @data[scripts_dir] ||= build(scripts_dir)
  end

  def reset!
    @data = nil
  end

  def build(scripts_dir)
    effects_path = File.join(scripts_dir, 'Battle_MoveEffects.rb')
    move_path = File.join(scripts_dir, 'Battle_Move.rb')
    return { ratios: nil, functions: {} } unless File.exist?(effects_path)

    source = File.read(effects_path)
    functions = {}
    source.scan(/^class PokeBattle_Move_([0-9A-F]+)\s*<[^\n]*\n(.*?)(?=^class |\z)/m) do |code, body|
      functions[code] = {
        # 追加効果が実装されているか。:effect に数字が残っていても、効果その
        # ものが無いわざがある (エアカッターの 100 など)。実装がある場合だけ
        # 確率を出す。
        additional: body.include?('def pbAdditionalEffect'),
        hits: hit_count(body),
        drain: drain_share(body),
        heal: heal_share(body),
        body: body
      }
    end

    { ratios: crit_ratios(move_path), cap: stage_cap(scripts_dir), functions: functions }
  end

  # 能力変化の段階を読み取る。
  #
  # 書き方が2通りある。数字を直に渡すものと、変数に入れてから渡すもの。
  # どちらもフィールドで値が変わることがあり (なきごえはコンサート
  # フィールドで2段階、つるぎのまいはビッグトップなどで3段階)、その場合は
  # 素の値を採って「フィールドで変わる」と添える。素の値は、変数なら最初の
  # 代入、条件分岐なら小さいほう (フィールドは強化する側に働くため)。
  # 能力変化の段階を読み取る。
  #
  # 1つの効果クラスを複数のわざが共有していて、中は条件分岐だらけになって
  # いる。素の効果だけを採るために、次の2種類の枝の中にある行は読み飛ばす。
  #
  #   1. フィールドで変わる枝  (@battle.FE / PBFields / ProgressiveFieldCheck)
  #   2. 別のわざ向けの枝      (@move == :BITTERMALICE など)
  #
  # 例: ロックカットの中には「ロッキーフィールドなら+3」「クリスタルの
  # どうくつなら+2 とこうげき+1 ととくこう+1」という枝があり、素の効果は
  # else の +2。なきごえは statdrop = 1 が素で、コンサートフィールドだけ 2。
  # 効果クラスの中を1行ずつ見る。行がどの枝の中にいるかを添えて返す。
  #
  #   skip   … 素の効果ではない枝の中 (フィールド・天候・とくせい・別のわざ)
  #   branch … その枝が場面によるものか (印を付けるかの判断に使う)
  #
  # else は素の側なので、直前の枝の判定を打ち消す。
  def each_effect_line(body, move_sym)
    stack = []

    body.each_line do |line|
      indent = line[/\A */].length
      stack.pop while stack.any? && indent < stack.last[:indent]

      if (m = line.match(/\A\s*(?:if|elsif)\b(.*)/))
        stack.pop if stack.any? && stack.last[:indent] == indent
        stack.push(indent: indent, skip: skip_condition?(m[1], move_sym),
                   field: field_condition?(m[1]))
        next
      end

      if line.match?(/\A\s*else\b/)
        stack.pop if stack.any? && stack.last[:indent] == indent
        stack.push(indent: indent, skip: false, field: false)
        next
      end

      if line.match?(/\A\s*end\b/)
        stack.pop if stack.any? && stack.last[:indent] == indent
        next
      end

      inline = field_condition?(line)
      skip = inline || skip_condition?(line, move_sym) || stack.any? { |frame| frame[:skip] }
      branch = inline || stack.any? { |frame| frame[:field] }
      yield(line, skip, branch)
    end
  end

  def stat_changes(body, move_sym)
    changes = {}
    varies = {}
    loop_var = nil
    loop_stats = []

    each_effect_line(body, move_sym) do |line, skip, branch|
      # 「for stat in [PBStats::ATTACK, PBStats::SPEED]」の並びを覚えておく。
      if (loop = line.strip.match(STAT_LOOP))
        loop_var = loop[1]
        loop_stats = loop[2].scan(/PBStats::(\w+)/).flatten
        next
      end

      match = line.match(STAT_CALL)
      next unless match

      who, direction, stat, arg = match.captures
      stats = if STAT_JA.key?(stat)
                [stat]
              elsif stat == loop_var
                loop_stats
              else
                []
              end
      next if stats.empty?

      values = arg =~ /\A\d+\z/ ? [arg.to_i] : assignments(body, arg)

      stats.each do |name|
        key = [who, direction, name]
        varies[key] = true if branch || values.uniq.length > 1
        next if skip || values.empty?

        (changes[key] ||= []).concat(values)
      end
    end

    changes.map do |(who, direction, stat), steps|
      { who: who, direction: direction, stat: stat, steps: steps.min,
        varies: varies[[who, direction, stat]] || steps.uniq.length > 1 }
    end
  end

  # 場面で分岐しているか。フィールド・天候・とくせい・どうぐ・クレスト。
  # ここに当たる枝の値は「素の効果」ではないので、数字には採らない。
  def field_condition?(condition)
    condition.match?(/@battle\.FE|PBFields|ProgressiveFieldCheck|pbWeather|
                      \.ability\s*==|hasWorkingItem|crested/x)
  end

  # 読み飛ばす枝か。フィールドの枝と、別のわざ向けの枝。
  def skip_condition?(condition, move_sym)
    return true if field_condition?(condition)

    named = condition.scan(/(?:@move|id)\s*==\s*:(\w+)/).flatten
    named += condition.scan(/\[([^\]]*)\]\.include\?\((?:@move|id)\)/).flatten
                      .flat_map { |list| list.scan(/:(\w+)/).flatten }
    named.any? && !named.include?(move_sym.to_s)
  end

  # 変数に入れてから渡している場合の値。
  #
  #   statdrop = 1
  #   statdrop = 2 if <コンサートフィールド>
  #   statchange = <フィールド> ? 2 : 1
  #
  # のように、素の値とフィールドでの値が並ぶ。両方を拾って、小さいほうを
  # 素の値として使い、2通りあることは「フィールドで変わる」と添える。
  # 段階は 1〜6 なので、それ以外の数字は式の一部として捨てる。
  def assignments(body, name)
    body.each_line.flat_map { |line|
      # 行末の改行があるので chomp してから見る。== との取り違えを防ぐため、
      # 代入の = だけに当てる。
      expr = line.chomp[/\b#{Regexp.escape(name)}\s*(?<![=!<>])=(?!=)\s*(.+)\z/, 1]
      next [] unless expr

      expr.scan(/\b(\d+)\b/).flatten.map(&:to_i).select { |n| n.between?(1, 6) }
    }
  end

  # 連続ヒットの回数。書き方は2通り。
  #
  #   return 2                                     … 必ず2回
  #   hitchances = [2, 2, ... 5, 5]; sample(...)   … 2〜5回。並びが確率そのもの
  #
  # 手持ちの数や場面で変わるもの (ビートアップ・ドラゴンアロー) は出さない。
  def hit_count(body)
    section = body[/def pbNumHits.*?\n  end/m]
    return nil unless section

    if (list = section[/hitchances\s*=\s*\[([\d,\s]+)\]/, 1])
      counts = list.split(',').map { |n| n.strip.to_i }
      return nil if counts.empty?

      total = counts.length.to_f
      spread = counts.tally.sort.map { |hits, n| [hits, (n / total * 100).round] }
      return { spread: spread }
    end

    fixed = section.scan(/return\s+(\d+)\s*$/).flatten.map(&:to_i).uniq
    fixed.length == 1 && fixed.first > 1 ? { fixed: fixed.first } : nil
  end

  # 最大HPのうち、何割を回復するか。
  #
  #   attacker.pbRecoverHP(((attacker.totalhp + 1) / 2).floor)  … 自分の 1/2
  #   hpgain = (attacker.totalhp * 2 / 3.0).floor               … 自分の 2/3
  #   attacker.pbRecoverHP(attacker.totalhp - attacker.hp)      … 全回復
  #
  # 天候・フィールド・とくせいで変わる枝は数字に採らず、印だけ付ける
  # (あさのひざしは晴れで増え、すなあつめは砂嵐で増える)。
  def heal_share(body)
    base = nil
    varies = false

    each_effect_line(body, nil) do |line, skip, _branch|
      # 括弧の対応は数えず、行の残りをそのまま式として見る。
      # ((attacker.totalhp + 1) / 2).floor のような入れ子で、最初の
      # 閉じ括弧までしか採らないと割る数を見落とす。
      text = line.chomp
      expr = text[/pbRecoverHP\((.+)\z/, 1] || text[/hpgain\s*=\s*(.+)\z/, 1]
      next unless expr && expr.include?('totalhp')

      share = heal_fraction(expr)
      next unless share

      if skip
        varies = true
      elsif base.nil?
        who = expr.include?('opponent.totalhp') ? :other : :self
        base = { who: who, fraction: share }
      end
    end

    return nil unless base

    base.merge(varies: varies)
  end

  # 式から割合を読む。読めない書き方は nil (数字を出さない)。
  def heal_fraction(expr)
    return Rational(1) if expr.match?(/totalhp\s*-/) || expr.match?(/totalhp\s*\)?\s*\.floor\s*\z/)
    if (m = expr.match(%r{totalhp[^*/]*\*\s*(\d+)\s*/\s*([\d.]+)}))
      return Rational(m[1].to_i, m[2].to_f.round)
    end
    if (m = expr.match(%r{totalhp[^*/]*\*\s*([\d.]+)}))
      return m[1].to_f.rationalize(0.02)
    end
    if (m = expr.match(%r{totalhp[^/]*/\s*([\d.]+)}))
      value = m[1].to_f
      return value.zero? ? nil : Rational(1) / value.rationalize(0.02)
    end

    nil
  end

  # 与えたダメージのうち、何割を回復するか。
  #
  #   hpgain = ((damage + 1) / 2).floor      … 1/2
  #   hpgain = ((damage + 1) * 0.75).floor   … 3/4
  #
  # 自分の最大HPを基準に回復するわざ (じこさいせいなど) は天候で値が変わる
  # 書き方をしているので、ここでは扱わない。
  def drain_share(body)
    line = body.lines.find { |l| l.include?('hpgain') && l.include?('damage') && !field_condition?(l) && !l.include?('Rejuv') }
    return nil unless line

    expr = line[/damage \+ 1\)\s*(.*?)\)?\.floor/, 1].to_s
    if (m = expr.match(%r{\*\s*(\d+)\s*/\s*(\d+)}))
      Rational(m[1].to_i, m[2].to_i)
    elsif (m = expr.match(/\*\s*([\d.]+)/))
      m[1].to_f.rationalize(0.001)
    elsif (m = expr.match(%r{/\s*([\d.]+)}))
      Rational(1) / m[1].to_f.rationalize(0.001)
    end
  end

  # 回数が数字で決まらない連続ヒット。コードを読んで文にしてある。
  #   0x0C1 ふくろだたき  … 手持ちのうち瀕死でも状態異常でもない数 (最大6)
  #   0x17E ドラゴンアロー … 2回。相手が2体なら1体ずつ1回
  SPECIAL_HITS = {
    '0C1' => ['手持ちのうち、瀕死でも状態異常でもないポケモンの数だけ攻撃（最大6回）',
              'Hits once per healthy party member (up to 6)'],
    '17E' => ['2回攻撃。相手が2体いるときは1体ずつ1回',
              'Hits twice, or once on each of two opponents']
  }.freeze

  # 数字が場面で切り替わるもの。コードを読んで文にしてある。
  #   0x114 のみこむ  … ためた回数 (case effects[:Stockpile]) で 1/4・1/2・全回復
  #   0x094 プレゼント … pbRandom(10) で威力40/80/120と回復に分かれる
  SPECIAL_EFFECTS = {
    '114' => ['ためた回数で 最大HPの 1/4・1/2・全回復',
              'Restores 1/4, 1/2 or all HP depending on how many times it stockpiled'],
    '094' => ['威力40が40% / 威力80が30% / 威力120が10% / 相手を最大HPの1/4回復が20%',
              '40% power 40, 30% power 80, 10% power 120, 20% heals 1/4 of the target']
  }.freeze

  # 能力変化の上限。はらだいこはコードでは 12段階上げているが、
  # Battle_Effects.rb が ±6 で頭打ちにするので、実際には最大まで上がるだけ。
  # そのまま 12 と書くと嘘になる。
  def stage_cap(scripts_dir)
    path = File.join(scripts_dir, 'Battle_Effects.rb')
    return 6 unless File.exist?(path)

    File.read(path)[/@stages\[stat\]\s*=\s*(\d+)\s+if\s+@stages\[stat\]\s*>/, 1]&.to_i || 6
  end

  # 急所の倍率表。Battle_Move.rb の pbCalcDamage にそのまま書かれている。
  # リボーンは通常 1/24 で、本家 (第6世代以降の 1/16) とは違う。
  def crit_ratios(path)
    return nil unless File.exist?(path)

    line = File.read(path)[/ratios = \[([\d,\s]+)\]/, 1]
    line&.split(',')&.map { |n| n.strip.to_i }
  end

  # 1/8 は 12.5%。整数に丸めると別の数字になるので、割り切れないものは
  # 小数第1位まで書く。
  def percent(fraction)
    value = 100.0 / fraction
    value == value.round ? value.round.to_s : format('%.1f', value)
  end

  # 1件ぶんの数字。わざ表の説明に添える行として返す。
  def lines(move, scripts_dir, move_sym = nil)
    return [] unless move

    facts = data(scripts_dir)
    code = format('%03X', move[:function].to_i)
    info = facts[:functions][code] || {}
    ja = JaNames.enabled?
    out = []

    if move[:highcrit] && facts[:ratios] && facts[:ratios].length > 1
      high = percent(facts[:ratios][1])
      normal = percent(facts[:ratios][0])
      out << (ja ? "急所 #{high}%（通常は #{normal}%）" : "Critical hit #{high}% (normally #{normal}%)")
    end

    chance = move[:effect].to_i
    if chance.positive? && info[:additional]
      out << (ja ? "追加効果 #{chance}%" : "Added effect #{chance}%")
    end

    if (hits = info[:hits])
      out << if hits[:fixed]
               ja ? "#{hits[:fixed]}回攻撃" : "Hits #{hits[:fixed]} times"
             else
               spread = hits[:spread].map { |n, pct| ja ? "#{n}回 #{pct}%" : "#{n}x #{pct}%" }.join(' / ')
               range = "#{hits[:spread].first[0]}#{ja ? '〜' : '-'}#{hits[:spread].last[0]}"
               ja ? "連続 #{range}回（#{spread}）" : "Hits #{range} times (#{spread})"
             end
    end

    if (special = SPECIAL_HITS[code])
      out << (ja ? special[0] : special[1])
    end

    if (special = SPECIAL_EFFECTS[code])
      out << (ja ? special[0] : special[1])
    end

    if (heal = info[:heal]) && !SPECIAL_EFFECTS.key?(code)
      whose = if ja
                heal[:who] == :other ? '相手の' : '自分の'
              else
                heal[:who] == :other ? "the target's" : 'its'
              end
      mark = heal[:varies] ? '*' : ''
      out << if heal[:fraction] == 1
               ja ? "HPを全回復#{mark}" : "Restores all HP#{mark}"
             else
               ja ? "#{whose}最大HPの #{heal[:fraction]} を回復#{mark}" : "Restores #{heal[:fraction]} of #{whose} max HP#{mark}"
             end
    end

    if (share = info[:drain])
      out << (ja ? "与えたダメージの #{share} を回復" : "Restores #{share} of the damage dealt")
    end

    if (recoil = move[:recoil])
      fraction = recoil.to_f.rationalize(0.01)
      out << (ja ? "反動 与えたダメージの #{fraction}" : "Recoil #{fraction} of the damage dealt")
    end

    stats = info[:body] ? stat_changes(info[:body], move_sym) : []
    stats.each do |change|
      label = ja ? STAT_JA[change[:stat]] : STAT_EN[change[:stat]]
      next unless label

      sign = change[:direction] == 'Increase' ? '+' : '-'
      target = if ja
                 change[:who] == 'opponent' ? '相手の' : ''
               else
                 change[:who] == 'opponent' ? "target's " : ''
               end
      cap = facts[:cap] || 6
      steps = [change[:steps], cap].min
      # 上限を超える値が書かれているものは、実際には端まで動くだけ。
      maxed = change[:steps] > cap
      text = if ja
               maxed ? "#{target}#{label} 最大まで（#{sign}#{cap}段階）" : "#{target}#{label} #{sign}#{steps}段階"
             elsif maxed
               "#{target}#{label} maxed out (#{sign}#{cap} stages)"
             else
               "#{target}#{label} #{sign}#{steps} stage#{steps > 1 ? 's' : ''}"
             end
      # 印だけ付けて、断り書きは表の下に1つ置く (1匹で60行を超えるため)。
      text += '*' if change[:varies]
      out << text
    end

    out
  end

  # 押すと出る説明の末尾に足す文字列。何も無ければ空。
  def suffix(move, scripts_dir, move_sym = nil)
    parts = lines(move, scripts_dir, move_sym)
    parts.empty? ? '' : "\n#{parts.join(' / ')}"
  end
end
