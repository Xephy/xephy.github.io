# frozen_string_literal: true

require_relative 'ja_names'
require_relative 'mon_data'
require_relative 'move_facts'
require_relative 'machine_index'
require_relative 'evolution_index'
require_relative 'evolution_index_page'
require_relative 'encounter_index'
require_relative 'tutor_index'
require_relative 'trainer_index'
require_relative 'doc_context'
require_relative 'mon_index_page'

# ポケモン1種につき1ページ。
#
# 攻略本文と資料ページは「この場所に何が出るか」「このマシンは何を教えるか」の
# 向きでしか引けなかった。読者が実際に手を止めて調べるのは逆で、目の前にいる
# 1匹について「どこで捕れるか」「何を覚えるか」「何に進化するか」を続けて知りたい。
# その3つを1枚にまとめる。
#
# 実測で 805種 / 1069フォルム。姿はページ内のタブで切り替える。姿によって
# タイプ・進化・覚えるわざ・出現場所が変わるので、中身を丸ごと差し替える。
#
# ページは .md ではなく .html で書き出す (wt_generator)。805ページを kramdown に
# 通すとビルドが +42秒になるが、生の HTML なら +2.6秒で済む。
module MonPage
  module_function

  BLOCK_JUMPS = [['Basics', 'basic'], ['Matchups', 'match'], ['Evolution', 'evo'],
                 ['Wild', 'enc'], ['Moves', 'moves'], ['HM', 'hm'],
                 ['Fields', 'field'], ['Egg', 'egg']].freeze

  # 出現方法の札。出現場所ページと同じ色分けにする。
  WAY_CLASS = {
    'くさむら' => 'grass', 'どうくつ' => 'cave', 'なみのり' => 'surf',
    'ヘッドバット' => 'headbutt', 'いわくだき' => 'smash', 'つり' => 'fish',
    'Grass' => 'grass', 'Cave' => 'cave', 'Surfing' => 'surf',
    'Headbutt' => 'headbutt', 'Rock Smash' => 'smash', 'Fishing' => 'fish'
  }.freeze

  RATE_UI = {
    'morning' => 'morning', 'day' => 'day', 'night' => 'night',
    'oldrod' => 'oldrod', 'goodrod' => 'goodrod', 'superrod' => 'superrod'
  }.freeze

  # 同じたまごグループの一覧に出す上限。全部出すと 200種を超える種族があり、
  # ページの大きさが倍近くなる。畳んだ中身なので、切っても導線は残る。
  EGG_MATE_LIMIT = 80

  # フィールド相性に出す件数。効果の大きい順に並べたうちの上位。
  FIELD_LIMIT = 6

  # 節の飛び先。姿を切り替えても位置が変わらないよう、節そのものではなく
  # 高さの無い目印に id を持たせる。
  ANCHOR_TEMPLATE = '<div class="md-anchor" id="mon-KEY"></div>'

  def esc(text)
    text.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;').gsub('"', '&quot;')
  end

  def ui(text)
    esc(JaNames.ui(text))
  end

  def type_badge(sym, extra = nil)
    t = sym.to_s.downcase
    label = sym == :QMARKS ? '???' : JaNames.tr('types', sym.to_s.capitalize)
    %(<span class="type-badge type-#{t}#{extra ? " #{extra}" : ''}">#{esc(label)}</span>)
  end

  def href(game, species)
    "/#{game}/mon/#{MonData.slug(species)}/"
  end

  def mon_link(game, pokemon_hash, species, form_index = 0, label = nil, icon: true)
    data = pokemon_hash[species] && MonData.base_data(pokemon_hash[species])
    name = label || (data ? data[:name] : species.to_s)
    img = ''
    if icon && (src = mon_icon_src(species, form_index))
      img = %(<img src="#{src}" alt="" class="mon-icon md-icon" width="32" height="32" loading="lazy">)
    end
    %(<a class="md-monlink" href="#{href(game, species)}">#{img}<span>#{esc(name)}</span></a>)
  end

  def card(title, body, note: nil, count: nil)
    <<~HTML
      <section class="md-card">
        <h3 class="md-card-title">#{title}#{count ? %( <span class="md-count">#{esc(count)}</span>) : ''}</h3>
        #{body}
        #{note ? %(<p class="md-note">#{note}</p>) : ''}
      </section>
    HTML
  end

  def fact(label, value)
    %(<div class="md-fact"><dt>#{label}</dt><dd>#{value}</dd></div>)
  end

  # --- わざの表 -------------------------------------------------------------

  def move_row(move_hash, sym, scripts_dir, lead = nil, extra = nil)
    move = move_hash[sym]
    return '' unless move

    # 説明のあとに、具体的な数字を足す (急所率・追加効果の確率・能力変化の
    # 段階)。「急所に当たりやすい」だけでは、どのくらいかが分からない。
    facts = MoveFacts.suffix(move, scripts_dir, sym)

    power = move[:basedamage].to_i.positive? ? move[:basedamage] : '—'
    accuracy = move[:accuracy].to_i.zero? ? ui('Perfect') : "#{move[:accuracy]}%"
    %(<tr data-type="#{move[:type].to_s.downcase}">) +
      (lead ? %(<td class="md-lead">#{lead}</td>) : '') +
      %(<td class="md-move">#{type_badge(move[:type], 'md-tb')}) +
      # 本文の戦闘表と同じ move-name にする。点線の下線と cursor: help が
      # 付き、マウスが無い環境でもタップで説明が出る (myscripts.js)。
      %(<span class="move-name md-move-name" title="#{esc(move[:desc])}#{esc(facts)}">#{esc(move[:name])}</span></td>) +
      %(<td class="md-cat">#{esc(MonData.category_label(move[:category]))}</td>) +
      %(<td class="md-num">#{power}</td><td class="md-num">#{accuracy}</td>) +
      (extra ? %(<td class="md-where">#{extra}</td>) : '') +
      %(</tr>)
  end

  def move_table(kind, rows_html)
    cols, heads =
      case kind
      when :level
        [%w[5.5em auto 3.4em 3.4em 4em],
         ['Learned at', 'Moves', 'Category', 'Power', 'Accuracy']]
      when :machine
        [%w[6.4em auto 3.4em 3.4em 4em 15em],
         ['Machine', 'Moves', 'Category', 'Power', 'Accuracy', 'Where to get it']]
      when :tutor
        [%w[auto 3.4em 3.4em 4em 17em],
         ['Moves', 'Category', 'Power', 'Accuracy', 'Where to learn it']]
      else
        [%w[auto 3.4em 3.4em 4em], ['Moves', 'Category', 'Power', 'Accuracy']]
      end

    <<~HTML
      <div class="md-scroll"><table class="md-moves">
        <colgroup>#{cols.map { |w| %(<col style="width:#{w}">) }.join}</colgroup>
        <thead><tr>#{heads.map { |h| "<th>#{ui(h)}</th>" }.join}</tr></thead>
        <tbody>#{rows_html}</tbody>
      </table></div>
    HTML
  end

  # --- ページ ---------------------------------------------------------------

  # 攻略本文からの索引をまとめて受け取る。生成の途中で集まるものなので、
  # 章を組み終えたあとに呼ぶ必要がある。
  def context(game, scripts_dir, chapters, item_hash, move_hash)
    machines = MachineIndex.build(item_hash, move_hash)
    places = MachineIndex.locations(chapters, game, machines.map { |m| m[:label] })
    {
      game: game,
      machines: machines.map { |m| m.merge(places: (places[m[:label]] || {}).values) },
      # 教え人の索引は英語名で持っている。訳したあとの名前で引けるようにする。
      tutors: TutorIndex.by_move.to_h { |row| [JaNames.tr('moves', row[:move]), row[:tutors]] },
      encounters: EncounterIndex.by_species.group_by { |row| row[:species_key].to_s.downcase },
      trainers: TrainerIndex.by_species,
      tutor_moves: MonData.tutor_moves(scripts_dir),
      hm_machines: machines.select { |m| m[:kind] == 1 }
    }
  end

  def build_pages(game, scripts_dir, chapters, hashes)
    pokemon_hash = hashes[:pokemon]
    return {} if pokemon_hash.nil? || pokemon_hash.empty?

    ctx = context(game, scripts_dir, chapters, hashes[:item], hashes[:move])
    # 「同じ条件で進化するポケモンは何件あるか」。個別ページから資料ページへ
    # 送るときに、行った先の量が分かるようにする。
    ctx[:pokemon] = pokemon_hash
    ctx[:evo_groups] = EvolutionIndex.collect(pokemon_hash)
                                     .group_by { |row| EvolutionIndex.group(row[:method]) }
                                     .transform_values(&:size)
    dex_order = dex_order(pokemon_hash)

    pages = pokemon_hash.each_key.to_h do |species|
      [MonData.slug(species), build_page(game, scripts_dir, species, hashes, ctx, dex_order)]
    end

    # 一覧ページ。個別ページと同じ場所に置く (permalink は /<game>/mon/)。
    index = MonIndexPage.build_page(game, pokemon_hash)
    pages['index'] = index if index
    pages
  end

  # 図鑑番号の並び。前後のポケモンへの導線に使う。姿違いは番号が同じなので
  # 1つにまとめる。
  def dex_order(pokemon_hash)
    pokemon_hash.filter_map { |species, forms|
      data = MonData.base_data(forms)
      next unless data && data[:dexnum].to_i.positive?

      [data[:dexnum].to_i, species, data[:name]]
    }.uniq { |num, _, _| num }.sort_by(&:first)
  end

  def build_page(game, scripts_dir, species, hashes, ctx, dex_order)
    pokemon_hash = hashes[:pokemon]
    forms = pokemon_hash[species]
    form_keys = MonData.form_keys(forms)
    base = forms[form_keys.first]
    name = base[:name]
    dexnum = base[:dexnum].to_i

    parts = merged_sections(game, scripts_dir, species, forms, form_keys, hashes, ctx)

    <<~PAGE
      ---
      layout: default
      title: "#{name}"
      permalink: #{href(game, species)}
      ---

      <p id="title-text">#{esc(name)}</p>

      #{back_link(game)}

      #{hero(game, species, forms, form_keys, name, dexnum, dex_order)}

      #{form_tabs(species, form_keys)}

      #{parts.join("\n")}

      #{trainer_block(game, species, ctx)}
    PAGE
  end

  def back_link(game)
    %(<p class="ref-back"><a href="/#{game}/">#{ui('Back to contents')}</a> · ) +
      %(<a href="/#{game}/mon/">#{ui('Pokemon list')}</a></p>)
  end

  def hero(game, species, forms, form_keys, name, dexnum, dex_order)
    position = dex_order.index { |num, _, _| num == dexnum }
    previous = position && position.positive? ? dex_order[position - 1] : nil
    following = position && position < dex_order.size - 1 ? dex_order[position + 1] : nil

    art = form_keys.each_with_index.filter_map { |form_key, i|
      src = mon_battler_src(species, i)
      next unless src

      alt = i.zero? ? name : "#{name} (#{MonData.form_label(form_key)})"
      %(<img src="#{src}" alt="#{esc(alt)}" class="md-hero-img#{i.zero? ? ' is-on' : ''}" ) +
        %(data-form-art="#{i}" loading="lazy">)
    }.join

    <<~HTML
      <div class="md-hero">
        #{art.empty? ? '' : %(<div class="md-hero-art">#{art}</div>)}
        <div class="md-hero-id">
          <p class="md-hero-dex">No.#{format('%03d', dexnum)}</p>
          <p class="md-hero-name">#{esc(name)}<span class="md-en">#{esc(english_name(species))}</span></p>
        </div>
        <nav class="md-hero-nav">
          #{previous ? %(<a href="#{href(game, previous[1])}"><span>←</span>#{esc(previous[2])}</a>) : ''}
          #{following ? %(<a href="#{href(game, following[1])}">#{esc(following[2])}<span>→</span></a>) : ''}
        </nav>
      </div>
    HTML
  end

  # 英語名。日本語版では和名の隣に小さく添える (検索で英語名を使う人がいる)。
  # 英語版では同じ文字が2つ並ぶので出さない。
  def english_name(species)
    return '' unless JaNames.enabled?

    species.to_s.capitalize
  end

  def form_tabs(species, form_keys)
    return '' if form_keys.size < 2

    buttons = form_keys.each_with_index.map { |form_key, i|
      icon = mon_icon_src(species, i)
      %(<button type="button" class="md-form#{i.zero? ? ' is-on' : ''}" data-form="#{i}">) +
        (icon ? %(<img src="#{icon}" alt="" width="32" height="32" loading="lazy">) : '') +
        %(#{esc(MonData.form_label(form_key))}</button>)
    }.join
    %(<div class="md-forms">#{buttons}</div>)
  end

  # --- 姿ごとの中身 ---------------------------------------------------------

  # 姿ごとの中身を節ごとに組む。返すのは [節の名前, HTML] の並び。
  def form_sections(game, scripts_dir, species, forms, form_key, index, hashes, ctx)
    [['summary', summary(forms, form_key, index)],
     ['basic',   basics(forms, form_key, hashes)],
     ['match',   matchups(forms, form_key, hashes)],
     ['evo',     evolution(game, species, forms, form_key, index, hashes, ctx)],
     ['enc',     encounters(species, forms, form_key, hashes, ctx)],
     ['moves',   moves(species, scripts_dir, forms, form_key, hashes, ctx)],
     ['hm',      hidden_machines(species, scripts_dir, forms, form_key, hashes, ctx)],
     ['field',   fields(species, scripts_dir, forms, form_key, hashes, ctx)],
     ['egg',     egg_mates(game, species, forms, form_key, hashes)]]
  end

  # 姿が増えても、中身が同じ節は1つにまとめる。
  #
  # アルセウスは18姿あるが、違うのはタイプと相性だけで覚えるわざは同じ。
  # 姿ごとに丸ごと並べると1ページ 2.6MB になり、同じ表を18回配ることになる。
  # 節ごとにまとめると 1/10 以下に収まる。
  #
  # 飛び先の id は節につき1つだけ置く。どの姿を見ていても同じ位置にある。
  def merged_sections(game, scripts_dir, species, forms, form_keys, hashes, ctx)
    per_form = form_keys.each_with_index.map { |form_key, index|
      form_sections(game, scripts_dir, species, forms, form_key, index, hashes, ctx).to_h
    }
    keys = per_form.first.keys

    keys.flat_map { |key|
      variants = {}
      per_form.each_with_index do |sections, index|
        html = sections[key].to_s
        next if html.empty?

        (variants[html] ||= []) << index
      end
      next [] if variants.empty?

      anchor = key == 'summary' ? '' : ANCHOR_TEMPLATE.sub('KEY', key)
      parts = [anchor] + variants.map { |html, indexes|
        on = indexes.include?(0) ? ' is-on' : ''
        %(<div class="md-part#{on}" data-forms="#{indexes.join(' ')}">#{html}</div>)
      }
      # 要点の帯のすぐ後ろに、節への飛び先を置く。無い節 (タマゴを作れない
      # 種族など) へは飛べないので、実際に出た節だけを並べる。
      parts << jump_nav(keys, per_form) if key == 'summary'
      parts
    }.reject { |part| part.to_s.empty? }
  end

  def jump_nav(keys, per_form)
    present = keys.reject { |key| key == 'summary' }
                  .select { |key| per_form.any? { |sections| !sections[key].to_s.empty? } }
    return '' if present.empty?

    labels = BLOCK_JUMPS.to_h { |label, key| [key, label] }
    links = present.map { |key| %(<a href="#mon-#{key}">#{ui(labels[key] || key)}</a>) }.join
    %(<nav class="md-jump">#{links}</nav>)
  end

  def summary(forms, form_key, index)
    type1 = MonData.attr_of(forms, form_key, :Type1)
    type2 = MonData.attr_of(forms, form_key, :Type2)
    stats = MonData.attr_of(forms, form_key, :BaseStats) || []
    height = (MonData.attr_of(forms, form_key, :Height).to_f / 10).round(1)
    weight = (MonData.attr_of(forms, form_key, :Weight).to_f / 10).round(1)
    groups = (MonData.attr_of(forms, form_key, :EggGroups) || [])

    <<~HTML
      <div class="md-summary">
        <div class="md-summary-types">#{[type1, type2].compact.map { |t| type_badge(t) }.join}</div>
        <dl class="md-facts">
          #{fact(ui('Base stat total'), %(<strong>#{stats.sum}</strong>))}
          #{fact(ui('Height / Weight'), "#{height}m / #{weight}kg")}
          #{fact(ui('Catch rate'), %(#{MonData.attr_of(forms, form_key, :CatchRate)}<span class="md-sub">/ 255</span>))}
          #{fact(ui('Egg groups'), groups.map { |g| esc(MonData.egg_group_label(g)) }.join(' · '))}
        </dl>
      </div>
    HTML
  end

  def basics(forms, form_key, hashes)
    ability_hash = hashes[:ability]
    abilities = (MonData.attr_of(forms, form_key, :Abilities) || []).map { |sym|
      ability = ability_hash[sym]
      %(<div class="md-ability"><strong>#{esc(ability ? ability[:name] : sym)}</strong>) +
        %(<span>#{esc(ability ? ability[:desc] : '')}</span></div>)
    }.join
    if (hidden = MonData.attr_of(forms, form_key, :HiddenAbility))
      ability = ability_hash[hidden]
      abilities += %(<div class="md-ability"><strong>#{esc(ability ? ability[:name] : hidden)}</strong>) +
                   %(<span class="md-tag">#{ui('Hidden Ability')}</span>) +
                   %(<span>#{esc(ability ? ability[:desc] : '')}</span></div>)
    end

    stats = MonData.attr_of(forms, form_key, :BaseStats) || []
    stat_html = stats.each_with_index.map { |value, i|
      width = [(value / 200.0 * 100).round, 100].min
      %(<div class="md-stat"><span class="md-stat-name">#{esc(MonData.stat_label(i))}</span>) +
        %(<span class="md-stat-num">#{value}</span>) +
        %(<span class="md-stat-bar"><i style="width:#{width}%"></i></span></div>)
    }.join

    evs = MonData.attr_of(forms, form_key, :EVs) || []
    ev_text = evs.each_with_index.filter_map { |value, i|
      value.positive? ? "#{MonData.stat_label(i)}+#{value}" : nil
    }.join('　')

    training = <<~HTML
      <dl class="md-facts md-facts-grid">
        #{fact(ui('EV yield'), esc(ev_text.empty? ? JaNames.ui('None') : ev_text))}
        #{fact(ui('Growth rate'),
               "#{esc(MonData.growth_label(MonData.attr_of(forms, form_key, :GrowthRate)))}" \
               "<span class=\"md-sub\">#{ui('Base EXP')} #{MonData.attr_of(forms, form_key, :BaseEXP)}</span>")}
        #{fact(ui('Base happiness'), MonData.attr_of(forms, form_key, :Happiness))}
        #{fact(ui('Gender ratio'), esc(MonData.gender_label(MonData.attr_of(forms, form_key, :GenderRatio))))}
        #{fact(ui('Hatch steps'), MonData.attr_of(forms, form_key, :EggSteps))}
        #{fact(ui('Dex number'), "No.#{format('%03d', MonData.attr_of(forms, form_key, :dexnum).to_i)}")}
      </dl>
    HTML

    %(<section class="md-sec"><h2>#{ui('Base data')}</h2>) +
      %(<div class="md-cols">) +
      card(ui('Abilities'), abilities) +
      card(ui('Base stats'), %(<div class="md-stats">#{stat_html}</div>)) +
      %(</div>) + card(ui('Training'), training) + %(</section>)
  end

  MATCHUP_GROUPS = [[4.0, 'x4', '4x'], [2.0, 'x2', '2x'], [0.5, 'half', '1/2'],
                    [0.25, 'quarter', '1/4'], [0.0, 'zero', 'No effect']].freeze

  def matchups(forms, form_key, hashes)
    type1 = MonData.attr_of(forms, form_key, :Type1)
    type2 = MonData.attr_of(forms, form_key, :Type2)
    table = MonData.matchups(hashes[:type], type1, type2)

    rows = MATCHUP_GROUPS.filter_map { |mult, cls, label|
      list = table.select { |_, value| value == mult }.keys
      next if list.empty?

      %(<div class="md-match md-match-#{cls}"><span class="md-match-label">#{ui(label)}</span>) +
        %(<span class="md-match-list">#{list.map { |t| type_badge(t) }.join}</span></div>)
    }.join

    %(<section class="md-sec"><h2>#{ui('Type matchups')}</h2>) +
      card(ui('Damage taken'), rows, note: ui('Shadow is the type used only by Shadow Pokemon. It never shows up in normal battles, but the data lists it, so it is shown here.')) +
      %(</section>)
  end

  # 「この条件で進化するのは他に誰か」。個別ページは1匹ぶんしか答えられない
  # ので、方法で絞った一覧へ送る (通信交換が要るものが26件ある、など)。
  def evolution_crosslinks(game, species, forms, form_key, ctx)
    # 自分が進化する条件と、自分が生まれた条件の両方を拾う。
    # 最終進化でも「自分はどうやって出てくるのか」から辿れるようにする。
    methods = (MonData.attr_of(forms, form_key, :evolutions) || []).map { |evo| evo[:method] }
    if (pre = MonData.attr_of(forms, form_key, :preevo))
      methods += MonData.evo_children(ctx[:pokemon], pre[:species])
                        .select { |child| child[:to] == species }
                        .map { |child| child[:method] }
    end
    groups = methods.map { |method| EvolutionIndex.group(method) }.uniq
    return nil if groups.empty?

    links = groups.map { |group|
      count = ctx[:evo_groups][group].to_i
      label = EvolutionIndexPage.group_label(group)
      %(<a href="/#{game}/evolutions/?g=#{group}">#{esc(label)}<span>#{count}</span></a>)
    }.join
    %(<span class="md-cross-label">#{ui('Others that evolve the same way')}</span>#{links})
  end

  def evolution(game, species, forms, form_key, index, hashes, ctx)
    pokemon_hash = hashes[:pokemon]
    name = MonData.base_data(forms)[:name]
    root = MonData.evo_root(pokemon_hash, species, form_key)

    lines = MonData.evo_paths(pokemon_hash, root, species, form_key).map { |path|
      nodes = path.map { |step|
        if (child = step[:child])
          # describe はエスケープ済みの HTML を返す (どうぐ名は店の索引への
          # リンクになっている)。ここで再びエスケープすると、読者の画面に
          # <a href=...> がそのまま出る。
          condition = EvolutionIndex.describe(child, hashes[:item], hashes[:move],
                                              pokemon_hash, hashes[:map])
          %(<span class="md-evo-arrow">→<em>#{condition}</em></span>)
        elsif step[:species] == species
          %(<span class="md-evo-node is-self">#{mon_link(game, pokemon_hash, species, index, name)}</span>)
        else
          %(<span class="md-evo-node">#{mon_link(game, pokemon_hash, step[:species])}</span>)
        end
      }.join
      %(<div class="md-evo-line">#{nodes}</div>)
    }
    # 進化も進化前も無ければ、自分1匹だけの行が残る。それは出さない。
    lines = [] if lines.size == 1 && !lines.first.include?('md-evo-arrow')

    (MonData.attr_of(forms, form_key, :MegaEvolutions) || {}).each do |stone, mega_form|
      item = hashes[:item][stone]
      lines << %(<div class="md-evo-line">) +
               %(<span class="md-evo-node is-self">#{mon_link(game, pokemon_hash, species, index, name)}</span>) +
               %(<span class="md-evo-arrow">→<em>#{format(JaNames.ui('Hold %s in battle'), esc(item ? item[:name] : stone))}</em></span>) +
               %(<span class="md-evo-mega">#{esc(MonData.form_label(mega_form))}</span></div>)
    end

    body = lines.empty? ? %(<p class="md-empty">#{ui('Does not evolve.')}</p>) : lines.join
    %(<section class="md-sec"><h2>#{ui('Evolution')}</h2>) +
      card(ui('Evolution line'), body, note: evolution_crosslinks(game, species, forms, form_key, ctx)) +
      %(</section>)
  end

  # 出現表の行は姿ごとに分かれている (「ニャース (アローラのすがた)」)。
  # 基本形は括弧の無い行、姿違いはその姿の名前が入っている行を拾う。
  def encounter_row(rows, form_key, name)
    return nil unless rows

    if form_key.to_s.start_with?('Normal')
      rows.find { |row| row[:species] == name } || rows.find { |row| !row[:species].include?('(') }
    else
      label = MonData.form_label(form_key)
      rows.find { |row| row[:species].include?(label) }
    end
  end

  # 「同じころ / 同じ方法で捕まえられるのは他に誰か」。個別ページは1匹ぶんしか
  # 答えられないので、出現場所ページを絞った状態へ送る。
  def encounter_crosslinks(game, places)
    return nil if places.empty?

    links = []
    first = places.min_by { |place| place.dig(:context, :seq) || 0 }
    seq = first.dig(:context, :seq)
    if seq
      chapter = first.dig(:context, :chapter).to_s.sub(/[:：].*\z/, '').strip
      links << %(<a href="/#{game}/pokemon/?ch=#{seq}">#{format(JaNames.ui('%s and earlier'), esc(chapter))}</a>)
    end

    ways = places.map { |place| [place[:group], WAY_CLASS[place[:group]] || 'other'] }.uniq
    ways.each do |label, cls|
      links << %(<a href="/#{game}/pokemon/?w=#{cls}">#{esc(label)}</a>)
    end
    return nil if links.empty?

    %(<span class="md-cross-label">#{ui('Others caught the same way')}</span>#{links.join})
  end

  def encounters(species, forms, form_key, hashes, ctx)
    name = MonData.base_data(forms)[:name]
    row = encounter_row(ctx[:encounters][MonData.slug(species)], form_key, name)
    places = (row && row[:places]) || []

    body = if places.empty?
             %(<p class="md-empty">#{ui('Not found in the wild.')}</p>)
           else
             %(<ul class="md-places">) + places.map { |place|
               chapter = place.dig(:context, :chapter).to_s.sub(/[:：].*\z/, '')
               rates = (place[:rates] || {}).reject { |_, value| value.to_i.zero? }
               meta = [place[:levels].to_s.empty? ? nil : "Lv#{place[:levels]}",
                       rates.empty? ? nil : rates.map { |label, value|
                         label ? "#{JaNames.ui(RATE_UI[label] || label)} #{value}%" : "#{value}%"
                       }.join(' / ')].compact.join(' · ')
               cls = WAY_CLASS[place[:group]] || 'other'
               link = place.dig(:context, :href)
               %(<li><span class="pdx-way pdx-way-#{cls}">#{esc(place[:group])}</span>) +
                 %(<span class="md-place-name">) +
                 (link ? %(<a href="#{link}">#{esc(place[:map_label])}</a>) : esc(place[:map_label])) +
                 %(</span><span class="pdx-meta">#{esc(chapter)} · #{esc(meta)}</span></li>)
             }.join + %(</ul>)
           end

    held = MonData::WILD_ITEM_RATES.filter_map { |key, rate|
      sym = MonData.attr_of(forms, form_key, key)
      next unless sym

      item = hashes[:item][sym]
      %(<span class="md-held">#{esc(item ? item[:name] : sym)}<span>#{rate}</span></span>)
    }.join

    %(<section class="md-sec"><h2>#{ui('Wild locations')}</h2>) +
      card(ui('Where it appears in the wild'), body,
           note: encounter_crosslinks(ctx[:game], places),
           count: places.empty? ? nil : format(JaNames.ui(places.size == 1 ? '%d place' : '%d places'), places.size)) +
      (held.empty? ? '' : card(ui('Wild held items'), %(<p class="md-helds">#{held}</p>),
                               note: ui('With a Compound Eyes Pokemon in the lead, the odds rise to 60% / 20% / 5%.'))) +
      %(</section>)
  end

  def moves(species, scripts_dir, forms, form_key, hashes, ctx)
    move_hash = hashes[:move]
    item_hash = hashes[:item]

    level_moves = MonData.attr_of(forms, form_key, :Moveset) || []
    machines = ctx[:machines].select { |m|
      MonData.learnable?(species, forms, form_key, move_hash.key(m[:move]), item_hash, scripts_dir)
    }
    tutors = ctx[:tutor_moves].select { |sym|
      MonData.learnable?(species, forms, form_key, sym, item_hash, scripts_dir)
    }
    egg_moves = MonData.attr_of(forms, form_key, :EggMoves) || []
    relearner = MonData.attr_of(forms, form_key, :RelearnerMoves) || []
    shadow = MonData.attr_of(forms, form_key, :shadowmoves) || []

    tabs = []
    tabs << ['Level', level_moves.size, move_table(:level, level_moves.map { |level, sym|
      lead = level.to_i <= 1 ? ui('From the start') : "#{JaNames.ui('Lv.')}#{level}"
      move_row(move_hash, sym, scripts_dir, lead)
    }.join)]

    tabs << ['TMs', machines.size, move_table(:machine, machines.map { |machine|
      place = machine[:places].first
      where = place ? %(<a href="#{place[:href]}">#{esc(place[:text])}</a>) : %(<span class="md-empty">—</span>)
      move_row(move_hash, move_hash.key(machine[:move]), scripts_dir,
               %(<a class="md-tm-no" href="/#{ctx[:game]}/tms/##{machine_anchor(machine)}">#{esc(short_label(machine))}</a>),
               where)
    }.join)]

    tabs << ['Tutor moves', tutors.size, move_table(:tutor, tutors.map { |sym|
      move = move_hash[sym]
      tutor = move && (ctx[:tutors][move[:name]] || []).first
      where = if tutor
                %(<a href="#{tutor.dig(:context, :href)}">#{esc(tutor[:tutor])}</a>) +
                  %(<span class="md-price">#{esc(tutor[:price])}</span>)
              else
                %(<span class="md-empty">—</span>)
              end
      move_row(move_hash, sym, scripts_dir, nil, where)
    }.join)]

    unless egg_moves.empty?
      tabs << ['Egg moves', egg_moves.size,
               move_table(:plain, egg_moves.map { |sym| move_row(move_hash, sym, scripts_dir) }.join)]
    end
    unless relearner.empty?
      tabs << ['Relearner moves', relearner.size,
               move_table(:plain, relearner.map { |sym| move_row(move_hash, sym, scripts_dir) }.join)]
    end
    unless shadow.empty?
      tabs << ['Shadow Moves', shadow.size,
               move_table(:plain, shadow.map { |sym| move_row(move_hash, sym, scripts_dir) }.join)]
    end

    buttons = tabs.each_with_index.map { |(label, count, _), i|
      %(<button type="button" class="md-tab#{i.zero? ? ' is-on' : ''}" data-tab="#{i}">) +
        %(#{ui(label)}<span>#{count}</span></button>)
    }.join
    type_filter = move_type_filter(tabs)
    panels = tabs.each_with_index.map { |(_, _, body), i|
      %(<div class="md-panel#{i.zero? ? ' is-on' : ''}" data-panel="#{i}">#{body}</div>)
    }.join

    %(<section class="md-sec"><h2>#{ui('Learnable moves')}</h2>) +
      %(<div class="md-card"><div class="md-tabs">#{buttons}</div>#{type_filter}#{panels}) +
      %(<p class="md-note">#{ui('Tap a move name for its description. The numbers come from the game data and code; a value marked * can change with the field, the weather or an ability. Added-effect chances are doubled by Serene Grace and on the Rainbow Field.')}</p></div></section>)
  end

  # わざマシン一覧ページの行につけた id。番号だけでは わざマシン10 と
  # ひでんマシン10 が衝突するので、種類も混ぜる。
  # 覚えるわざをタイプで絞る札。
  #
  # 1匹が覚えるわざは平均で 60本を超える (わざマシンだけで30本)。「でんきわざは
  # 何を覚えるのか」を探すのに、6つのタブを目で舐める必要があった。
  #
  # 札はどのタブでも同じものを出し、条件はタブを跨いで続く。数字は開いている
  # タブの件数なので、書き出しでは空にしておき JavaScript が入れる。
  def move_type_filter(tabs)
    types = tabs.flat_map { |_, _, html| html.scan(/data-type="([a-z]+)"/).flatten }.uniq
    return '' if types.size < 2

    chips = MonData::TYPE_ORDER.select { |type| types.include?(type) }.map { |type|
      label = JaNames.tr('types', type.capitalize)
      %(<button type="button" class="ref-chip type-badge type-#{type}" data-value="#{type}" ) +
        %(aria-pressed="false">#{esc(label)}<span></span></button>)
    }.join

    %(<div class="md-mv-filter" hidden><span class="ref-chip-label">#{ui('Type')}</span>#{chips}) +
      %(<button type="button" class="ref-reset">#{ui('Clear')}</button>) +
      %(<span class="ref-count" role="status" aria-live="polite"></span></div>)
  end

  # 表の1列目に置く短い札。「わざマシン01」のままでは列を食うので番号だけにする。
  def short_label(machine)
    return "HM#{machine[:number]}" if machine[:kind] == 1

    format('TM%02d', machine[:number])
  end

  def machine_anchor(machine)
    "#{machine[:kind] == 1 ? 'hm' : 'tm'}-#{machine[:number]}"
  end

  # 覚えられないひでんわざも並べる。「なみのり要員が居ない」ことが分かるのは
  # 覚えられるものだけを見たときではなく、9本を並べたときなので。
  def hidden_machines(species, scripts_dir, forms, form_key, hashes, ctx)
    machines = ctx[:hm_machines]
    return '' if machines.empty?

    learnable = machines.map { |machine|
      [machine, MonData.learnable?(species, forms, form_key, hashes[:move].key(machine[:move]),
                                   hashes[:item], scripts_dir)]
    }
    chips = learnable.map { |machine, ok|
      %(<span class="md-hm#{ok ? ' is-ok' : ''}">#{short_label(machine)} #{esc(machine[:move][:name])}</span>)
    }.join

    %(<section class="md-sec"><h2>#{ui('HM moves')}</h2>) +
      card(ui('HMs it can learn'), %(<p class="md-hms">#{chips}</p>),
           count: "#{learnable.count { |_, ok| ok }} / #{machines.size}",
           note: ui('The highlighted ones are the HM moves it can learn. Useful when deciding who carries the field moves.')) +
      %(</section>)
  end

  def fields(species, scripts_dir, forms, form_key, hashes, ctx)
    field_hash = hashes[:field]
    return '' if field_hash.nil? || field_hash.empty?

    move_hash = hashes[:move]
    type1 = MonData.attr_of(forms, form_key, :Type1)
    type2 = MonData.attr_of(forms, form_key, :Type2)

    learnable = ((MonData.attr_of(forms, form_key, :Moveset) || []).map(&:last) +
                 (MonData.attr_of(forms, form_key, :compatiblemoves) || []) +
                 (MonData.attr_of(forms, form_key, :EggMoves) || []) +
                 (MonData.attr_of(forms, form_key, :RelearnerMoves) || [])).uniq.select { |sym|
      MonData.learnable?(species, forms, form_key, sym, hashes[:item], scripts_dir)
    }

    rows = field_hash.filter_map { |_key, field|
      next if field[:name].to_s.empty?

      boosted = (field[:damageMods] || {}).select { |mult, _| mult.to_f > 1 }
                                          .values.flatten.uniq & learnable
      type_boost = (field[:typeBoosts] || {}).select { |mult, _| mult.to_f > 1 }
                                             .values.flatten.uniq & [type1, type2].compact
      next if boosted.empty? && type_boost.empty?

      detail = +''
      unless type_boost.empty?
        detail << %(<span class="md-field-type">#{ui('Type boosted')} ) +
                  %(#{type_boost.map { |t| type_badge(t, 'md-tb') }.join}</span>)
      end
      unless boosted.empty?
        detail << %(<span class="md-field-moves">) +
                  boosted.first(8).map { |sym|
                    %(<span class="md-mchip">#{esc(move_hash[sym][:name])}</span>)
                  }.join +
                  (boosted.size > 8 ? %(<span class="md-sub">#{format(JaNames.ui('and %d more'), boosted.size - 8)}</span>) : '') +
                  %(</span>)
      end

      label = JaNames.field(field[:name]) || field[:name]
      [boosted.size + (type_boost.empty? ? 0 : 100),
       %(<div class="md-field"><div class="md-field-name">) +
         %(<a href="/#{ctx[:game]}/fields/">#{esc(label)}</a></div>) +
         %(<div class="md-field-body">#{detail}</div></div>)]
    }.sort_by { |score, _| -score }

    return '' if rows.empty?

    %(<section class="md-sec"><h2>#{ui('Field synergy')}</h2>) +
      card(ui('Fields that boost its moves or type'), rows.first(FIELD_LIMIT).map(&:last).join,
           count: "#{[rows.size, FIELD_LIMIT].min} / #{rows.size}",
           note: ui('Sorted by how much the field helps. The fields themselves are described on the Field Effects page.')) +
      %(</section>)
  end

  def egg_mates(game, species, forms, form_key, hashes)
    groups = MonData.attr_of(forms, form_key, :EggGroups) || []
    return '' if groups.empty? || groups.include?(:Undiscovered)

    pokemon_hash = hashes[:pokemon]
    mates = pokemon_hash.filter_map { |other, other_forms|
      next if other == species

      data = MonData.base_data(other_forms)
      next unless data && (data[:EggGroups] || []).any? { |g| groups.include?(g) }
      next if (data[:EggGroups] || []).include?(:Undiscovered)

      [data[:dexnum].to_i, other, data[:name]]
    }.sort_by(&:first)
    return '' if mates.empty?

    list = %(<div class="md-eggmates">) +
           mates.first(EGG_MATE_LIMIT).map { |_, other, name|
             mon_link(game, pokemon_hash, other, 0, name, icon: false)
           }.join +
           (mates.size > EGG_MATE_LIMIT ? %(<span class="md-sub">#{format(JaNames.ui('and %d more'), mates.size - EGG_MATE_LIMIT)}</span>) : '') +
           %(</div>)

    %(<section class="md-sec"><h2>#{ui('Egg group mates')}</h2>) +
      card(ui('Compatible breeding partners'),
           %(<details><summary>#{format(JaNames.ui('Show %d species'), mates.size)}</summary>#{list}</details>)) +
      %(</section>)
  end

  # 先の展開が見えるので、既定では畳んでおく。
  def trainer_block(game, species, ctx)
    rows = ctx[:trainers][species] || []
    body = if rows.empty?
             %(<p class="md-empty">#{ui('No trainer uses it.')}</p>)
           else
             %(<ul class="md-trainers">) + rows.map { |row|
               link = row.dig(:context, :href)
               section = row.dig(:context, :section).to_s
               levels = row[:levels].map { |l| "#{JaNames.ui('Lv.')}#{l}" }.join('・')
               count = row[:count] > 1 ? %(<span class="md-count">#{format(JaNames.ui('%d of them'), row[:count])}</span>) : ''
               %(<li>#{link ? %(<a href="#{link}">#{esc(row[:trainer])}</a>) : esc(row[:trainer])}#{count}) +
                 %(<span class="pdx-meta">#{esc(section)}#{levels.empty? ? '' : " · #{levels}"}</span></li>)
             }.join + %(</ul>)
           end

    %(<section class="md-sec"><h2>#{ui('Trainers using it')}</h2>) +
      card(ui('Teams in the walkthrough'),
           %(<details><summary>#{format(JaNames.ui('Show %d of them (spoilers)'), rows.sum { |r| r[:count] })}</summary>#{body}</details>)) +
      %(</section>)
  end
end
