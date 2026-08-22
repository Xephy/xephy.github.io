require 'json'
require_relative 'field_notes'
require_relative 'encounter_index'
require_relative 'badge_index'

require_relative 'common'
require_relative 'encounter_getter'
require_relative 'shop_getter'
require_relative 'trainer_getter'

# This is the magic class of the rewrite.
# Each function should return a string of some kind (can be multiline)
class FunctionWrapper
  # 資料ページ (わざマシン一覧) が同じデータを使う。読み込み直すと二重に
  # 訳が当たるので、ここで読んだものを渡す。
  attr_reader :item_hash, :move_hash

  # 画像の画素サイズ一覧 (bin/convert-images が書き出す)。
  IMAGE_SIZES = begin
    path = File.join(__dir__, 'image_sizes.json')
    File.exist?(path) ? JSON.parse(File.read(path)) : {}
  end.freeze


  def initialize(game, scripts_dir)
    # I need to pass in game to basically all of the potential functions, so
    # here we stick it in as as an argument. Anything that is consistent
    # across the whole document (ie. Version) should be used here:
    @cache = {}
    @game = game
    @scriptsDir = scripts_dir

    @mapHash = load_maps_hash(game, @scriptsDir)
    @encHash = load_enc_hash(game, @scriptsDir)
    @itemHash = load_item_hash(game, @scriptsDir)
    @trainerHash = load_trainer_hash(game, @scriptsDir)
    @bossHash = load_boss_hash(game, @scriptsDir)
    @shopHash = load_shop_hash(game, @scriptsDir)
    @trainerTypeHash = load_trainer_type_hash(game, @scriptsDir)
    @typeHash = load_type_hash(game, @scriptsDir)
    @moveHash = load_move_hash(game, @scriptsDir)
    @item_hash = @itemHash
    @move_hash = @moveHash
    @abilityHash = load_ability_hash(game, @scriptsDir)
    @pokemonHash = load_pokemon_hash(game, @scriptsDir)
    @raidDenHash = load_raid_den_hash(game, @scriptsDir)
    @encMapWrapper = EncounterMapWrapper.new(game, @scriptsDir)

    @encGetter = EncounterGetter.new(game, @scriptsDir, @encHash, @mapHash, @encMapWrapper, @pokemonHash,
                                     @itemHash)
    @shopGetter = ShopGetter.new(game, @scriptsDir, @itemHash, @moveHash)
    @trainerGetter = TrainerGetter.new(game, @scriptsDir, @trainerHash, @bossHash, @trainerTypeHash, @itemHash, @moveHash, @abilityHash,
                                       @pokemonHash, @typeHash)

    @shortNames = {
      'img' => 'generate_image_markdown',
      'enc' => 'generate_encounter_markdown',
      'shop' => 'generate_shop_markdown',
      'cshop' => 'generate_cshop_markdown',
      'battle' => 'generate_trainer_markdown',
      'btsinglesboss' => 'generate_battle_tower_singles_bosses_markdown',
      'btdoublesboss' => 'generate_battle_tower_doubles_bosses_markdown',
      'ttbattles' => 'generate_theme_teams_markdown',
      'dbattle' => 'generate_double_markdown',
      'mine' => 'generate_mining_markdown',
      'wildheld' => 'generate_wild_held_markdown',
      'tutor' => 'generate_tutor_markdown',
      'partner' => 'generate_partner_markdown',
      'newself' => 'generate_newself_markdown',
      'pickup' => 'generate_pickup_markdown',
      'fieldpw' => 'generate_field_password_markdown',
      'levelcaps' => 'generate_levelcap_markdown',
      'boss' => 'generate_boss_markdown',
      'move' => 'generate_move_markdown',
      'raid' => 'generate_raid_den_markdown'
    }
  end

  def evaluate_function_from_string(s)
    s = s.strip[1..-2]
    func_shortname, args = s.split('(', 2)
    raise "#{func_shortname} not found in list of shortnames." unless @shortNames[func_shortname]
      
    func = @shortNames[func_shortname]
    run_str = "#{func}(#{args})"
    # puts run_str
    if @cache.include?(run_str)
      return @cache[run_str]
    end
    res = eval(run_str) + "\n" # evaluates function, preserves its newline
    @cache[run_str] = res
    return res
  end

  # 攻略図。元の PNG/JPG は bin/convert-images で WebP に変換してある
  # (344MB -> 77MB)。width/height を必ず入れるのは、これが無いと画像が
  # 読み込まれるたびに本文が下へ飛ぶため。画素サイズは変換時に書き出した
  # 一覧から引く。
  def generate_image_markdown(filename)
    name = filename.to_s.strip.sub(/\.(png|jpe?g)\z/i, '.webp')
    size = IMAGE_SIZES.dig(@game, name)
    warn "画素サイズが不明: #{@game}/#{name}" if size.nil?
    dim = size ? %( width="#{size[0]}" height="#{size[1]}") : ''
    %(<img class="tabImage" src="/assets/images/#{@game}/#{name}"#{dim} ) +
      %(loading="lazy" decoding="async" alt="#{JaNames.ui('Map')}"/>)
  end

  # バッジ別のレベル上限。
  #
  # 本文では各章に「レベル上限も35まで引き上げられました」と散らばって
  # いるだけで、一覧が無かった。ゲームの LEVELCAPS は倒したジムリーダーの
  # 数で引く配列 (19要素 = 0〜18個)。
  #
  # バッジの名前と入手場所は BadgeIndex が本文から集めている。付録は章の
  # 最後に処理されるので、ここでは本編19章ぶんが揃っている。
  def generate_levelcap_markdown
    path = File.join(@scriptsDir, 'Reborn', 'SystemConstants.rb')
    return '' unless File.exist?(path)

    caps = File.read(path)[/^LEVELCAPS\s*=\s*\[([^\]]*)\]/, 1].to_s.split(',').map { |n| n.strip.to_i }
    return '' if caps.empty?

    badges = BadgeIndex.badges
    rows = caps.each_with_index.map do |cap, n|
      badge = n.zero? ? nil : badges[n - 1]
      where =
        if badge.nil?
          n.zero? ? JaNames.ui('Start of the game') : ''
        else
          ctx = badge[:context] || {}
          label = "<em>#{badge[:name]}</em>"
          ctx[:href] ? %(<a href="#{ctx[:href]}">#{label}</a>) : label
        end
      %(<tr><td class="cap-badges">#{n}</td><td class="cap-level">Lv.#{cap}</td>) +
        %(<td class="cap-where">#{where}</td></tr>)
    end

    <<~TABLE.strip
      <div class="cap-table-wrap"><table class="cap-table">
      <thead><tr><th>#{JaNames.ui('Badges')}</th><th>#{JaNames.ui('Level cap')}</th><th>#{JaNames.ui('Earned at')}</th></tr></thead>
      #{rows.join("\n")}
      </table></div>
    TABLE
  end

  # フィールドを固定するパスワードの一覧。
  #
  # 生の原稿では「すべてのバトルが○○で行われます」が38行続いていた。同じ文の
  # 繰り返しで読めたものではないうえ、そのフィールドが何をするのかは別ページに
  # あるのに繋がっていなかった。
  #
  # パスワードとフィールドの対応はゲーム側で決まっている。PASSWORD_HASH の
  # 2250 が「フィールドなし」で、2251 以降は fieldtext.rb の並び (屋内を除き、
  # 花畑の5段階は1本) にそのまま対応する。付録に元からあった37行の訳文と
  # 突き合わせて、全件一致することを確認済み。
  FIELD_PW_FIRST = 2250

  def generate_field_password_markdown
    src_path = File.join(@scriptsDir, 'Reborn', 'RebornScripts.rb')
    return '' unless File.exist?(src_path)

    hash = File.read(src_path)[/^PASSWORD_HASH = \{.*?^\}/m].to_s
    pws = hash.scan(/"([^"]+)"\s*=>\s*(\d+),/).map { |k, v| [k, v.to_i] }
              .select { |_, v| v.between?(FIELD_PW_FIRST, FIELD_PW_FIRST + 37) }
    return '' if pws.empty?

    names = FieldNotes.names(@scriptsDir)
    seen = {}
    keys = names.keys.reject { |k| k == 'INDOOR' }.reject { |k|
      n = names[k]
      dup = seen[n]
      seen[n] = true
      dup
    }

    rows = pws.sort_by(&:last).map do |name, sw|
      if sw == FIELD_PW_FIRST
        label = JaNames.ui('No Field')
      else
        key = keys[sw - FIELD_PW_FIRST - 1]
        next unless key

        label = %(<a href="/#{LONGNAMES[@game]}/fields/##{FieldNotes.anchor(key.to_sym)}">) +
                %(#{FieldNotes.display_name(key.to_sym, names)}</a>)
      end
      %(<tr data-pw="#{name}"><td class="pw-name"><strong>#{name}</strong></td>) +
        %(<td class="pw-field">#{label}</td></tr>)
    end.compact

    <<~TABLE.strip
      <div class="pw-table-wrap"><table class="pw-table">
      <thead><tr><th>#{JaNames.ui('Password')}</th><th>#{JaNames.ui('Field')}</th></tr></thead>
      #{rows.join("\n")}
      </table></div>
    TABLE
  end

  # 採掘の確率。
  #
  # 同じ確率の品目をまとめた8段で、合計はほぼ100% (採掘岩1つから出る1個の
  # 内訳)。元は品目を読点で1行に繋いでいたので、17品目並ぶ段が読めなかった。
  # 確率を先に置き、品目は折り返す一覧にする。
  def generate_mining_markdown
    mining_hash = load_mining_hash(@game, @scriptsDir)

    doc = Nokogiri::HTML::Document.new
    # 生の String を add_child すると Nokogiri は HTML フラグメントとして
    # 再パースする。文書のエンコーディングが未設定だと UTF-8 の日本語が
    # Latin-1 として解釈されて文字化けするので、生成時に必ず宣言する。
    doc.encoding = 'UTF-8'
    div = doc.create_element('div', class: 'mining_table')
    doc.add_child(div)

    table = doc.create_element('table', class: 'mine-table')
    div.add_child(table)

    thead = doc.create_element('thead')
    table.add_child(thead)

    title_row = doc.create_element('tr')
    thead.add_child(title_row)
    th_title = doc.create_element('th', colspan: 2, class: 'table-header',
                                       style: 'text-align: center;')
    th_title.add_child(doc.create_element('strong', JaNames.ui('Mining Probabilities')))
    title_row.add_child(th_title)

    head_row = doc.create_element('tr')
    thead.add_child(head_row)
    [['Rate', 'mine-rate'], ['Item', 'mine-items']].each do |label, cls|
      th = doc.create_element('th', class: "table-header #{cls}")
      th.content = JaNames.ui(label)
      head_row.add_child(th)
    end

    tbody = doc.create_element('tbody')
    table.add_child(tbody)

    mining_hash.each do |prob, item_list|
      row = doc.create_element('tr')
      tbody.add_child(row)

      td_rate = doc.create_element('td', class: 'mine-rate')
      td_rate.content = "#{prob}%"
      row.add_child(td_rate)

      td_items = doc.create_element('td', class: 'mine-items')
      item_list.each do |sym|
        chip = doc.create_element('em', class: 'mine-item')
        chip.content = @itemHash[sym][:name]
        td_items.add_child(chip)
      end
      row.add_child(td_items)
    end

    html_output = doc.to_html(encoding: 'UTF-8')
    html_output.split("\n")[1..].join("\n")
  end

  # 野生ポケモンの持ち物。
  #
  # 元は1つのセルに「- よく出る (50%): アメタマ」を積んでいた。確率を列に
  # 分けて、種族はアイコン付きで並べ、出現場所ページの該当行へ繋ぐ。
  # 実測で どうぐ84・(どうぐ, 確率) の組110・のべ種族334。
  HELD_RATES = { 'common' => 50, 'uncommon' => 5, 'rare' => 1 }.freeze

  def generate_wild_held_markdown
    lookup_hash = Hash.new { |hash, key| hash[key] = { 'common' => [], 'uncommon' => [], 'rare' => [] } }

    @pokemonHash.each do |mon_symbol, form_hash|
      forms = form_hash.reject { |key| !key.is_a?(String) }.compact
      next unless forms

      forms.each do |form, data|
        lookup_hash[data[:WildItemCommon]]['common'] << [mon_symbol, form] if data[:WildItemCommon]
        lookup_hash[data[:WildItemUncommon]]['uncommon'] << [mon_symbol, form] if data[:WildItemUncommon]
        lookup_hash[data[:WildItemRare]]['rare'] << [mon_symbol, form] if data[:WildItemRare]
      end
    end

    # 開発途中で表に出せないもの。上流からの引き継ぎ。
    lookup_hash.delete(:LEADERSCREST)
    lookup_hash.delete(:BOOSTERENERGY)

    doc = Nokogiri::HTML::Document.new
    doc.encoding = 'UTF-8'
    div = doc.create_element('div', class: 'held_table')
    doc.add_child(div)

    table = doc.create_element('table', class: 'held-table')
    div.add_child(table)

    thead = doc.create_element('thead')
    table.add_child(thead)

    title_row = doc.create_element('tr')
    thead.add_child(title_row)
    th_title = doc.create_element('th', colspan: 3, class: 'table-header',
                                       style: 'text-align: center;')
    th_title.add_child(doc.create_element('strong', JaNames.ui('Wild Pokemon Held Item Chances')))
    title_row.add_child(th_title)

    head_row = doc.create_element('tr')
    thead.add_child(head_row)
    [['Item', 'held-item'], ['Rate', 'held-rate'], ['Pokemon', 'held-mons']].each do |label, cls|
      th = doc.create_element('th', class: "table-header #{cls}")
      th.content = JaNames.ui(label)
      head_row.add_child(th)
    end

    tbody = doc.create_element('tbody')
    table.add_child(tbody)

    lookup_hash.sort_by { |item, _| @itemHash.keys.index(item) || 9999 }.each do |item, mon_hash|
      next unless mon_hash

      tiers = mon_hash.reject { |_, list| list.empty? }
      next if tiers.empty?

      tiers.each_with_index do |(rarity, list), i|
        row = doc.create_element('tr')
        tbody.add_child(row)

        if i.zero?
          td_item = doc.create_element('td', class: 'held-item')
          td_item['rowspan'] = tiers.length.to_s if tiers.length > 1
          td_item.add_child(doc.create_element('em', @itemHash[item][:name]))
          row.add_child(td_item)
        end

        td_rate = doc.create_element('td', class: 'held-rate')
        badge = doc.create_element('span', class: "held-tier held-#{rarity}")
        badge.content = "#{JaNames.ui(rarity.capitalize)} #{HELD_RATES[rarity]}%"
        td_rate.add_child(badge)
        row.add_child(td_rate)

        td_mons = doc.create_element('td', class: 'held-mons')
        list.each { |mon, form| td_mons.add_child(held_mon_node(doc, mon, form)) }
        row.add_child(td_mons)
      end
    end

    html_output = doc.to_html(encoding: 'UTF-8')
    html_output.split("\n")[1..].join("\n")
  end

  # 種族1体分。アイコンと名前を並べ、出現場所ページに行があればそこへ繋ぐ。
  def held_mon_node(doc, mon, form)
    form_keys = @pokemonHash[mon].keys.select { |k| k.is_a?(String) }
    form_index = form_keys.index(form) || 0
    name = @pokemonHash[mon][form_keys[0]][:name].to_s
    name += " (#{JaNames.tr('form_names', form)})" if form == 'Alolan Form'

    wrap = doc.create_element('span', class: 'held-mon')
    # 飛び先はその種族で絞り込んだ状態。素の一覧に飛ばすと595行の中から
    # 探し直すことになり、押した意味が無い。名前の部分一致だと
    # 「ゴース」が「ゴースト」にも当たるので、内部シンボルで指定する。
    inner = if EncounterIndex.has_species?(mon)
              doc.create_element('a',
                                 href: "/#{LONGNAMES[@game]}/pokemon/?mon=#{mon.to_s.downcase}")
            else
              doc.create_element('span')
            end
    wrap.add_child(inner)

    icon_src = mon_icon_src(mon, form_index)
    if icon_src
      icon = doc.create_element('img')
      icon['src'] = icon_src
      icon['alt'] = ''
      icon['class'] = 'mon-icon held-icon'
      icon['loading'] = 'lazy'
      icon['width'] = '32'
      icon['height'] = '32'
      inner.add_child(icon)
    end
    label = doc.create_element('span', class: 'held-mon-name')
    label.content = name
    inner.add_child(label)
    wrap
  end

  # ものひろいの表。
  #
  # 元は「アイテム名 | - 30%: Lv. 21-30 / - 10%: Lv. 1-20」と、1つのセルに
  # 確率とレベル帯を積んでいた。読者が知りたいのは逆で「Lv.45 の手持ちで
  # 何が拾えるか」なので、レベル帯を列にした行列にする。
  #
  # ゲームのデータはレベル帯が必ず10刻みで揃っている (実測: 41組すべて)。
  # 帯は10本、どの帯にもちょうど10〜11品目が並ぶ。
  PICKUP_BANDS = (1..91).step(10).map { |lo| [lo, lo + 9] }.freeze

  def generate_pickup_markdown
    pickup_data = load_pickup_data(@game, @scriptsDir)

    doc = Nokogiri::HTML::Document.new
    doc.encoding = 'UTF-8'
    div = doc.create_element('div', class: 'pickup_table')
    doc.add_child(div)

    # id ではなく class にする。見出し「ものひろいの表」のアンカーが
    # {#pickup-table} で、同じ id が2つになっていた。CSS の
    # #main_content #pickup-table が見出しにも当たり、狭い画面で
    # min-width: 720px が効いてページごと横に溢れていた。
    table = doc.create_element('table', class: 'pickup-matrix')
    div.add_child(table)

    thead = doc.create_element('thead')
    table.add_child(thead)

    title_row = doc.create_element('tr', class: 'header')
    thead.add_child(title_row)
    title_th = doc.create_element('th', colspan: PICKUP_BANDS.length + 1,
                                       class: 'table-header', style: 'text-align: center;')
    title_th.add_child(doc.create_element('strong', JaNames.ui('Pickup Odds')))
    title_row.add_child(title_th)

    head_row = doc.create_element('tr')
    thead.add_child(head_row)
    th_item = doc.create_element('th', class: 'table-header pickup-item')
    th_item.content = JaNames.ui('Item')
    head_row.add_child(th_item)
    PICKUP_BANDS.each do |lo, hi|
      th = doc.create_element('th', class: 'table-header pickup-band')
      th.content = "#{lo}-#{hi}"
      head_row.add_child(th)
    end

    tbody = doc.create_element('tbody')
    table.add_child(tbody)

    sorted = pickup_data.sort_by { |item, _| @itemHash.keys.index(item) }
    sorted.each do |item, odds_hash|
      row = doc.create_element('tr')
      tbody.add_child(row)

      td_item = doc.create_element('td', class: 'pickup-item')
      td_item.add_child(doc.create_element('em', @itemHash[item][:name]))
      row.add_child(td_item)

      PICKUP_BANDS.each do |lo, hi|
        odds = odds_hash.find { |_, range| range[0] <= lo && hi <= range[1] }&.first
        td = doc.create_element('td', class: 'pickup-band')
        if odds
          # 4段階しかないので、濃さで段を示すと縦にも横にも読める。
          td['class'] = "pickup-band pickup-odds-#{odds}"
          td.content = "#{odds}%"
        end
        row.add_child(td)
      end
    end

    html_output = doc.to_html(encoding: 'UTF-8')
    html_output.split("\n")[1..].join("\n")
  end

  def generate_encounter_markdown(map_id, include_list = nil, rods = nil, custom_map_name = nil)
    @encGetter.get_encounter_md(map_id, include_list, rods, custom_map_name)
  end

  def generate_shop_markdown(shop_title, shop_items)
    @shopGetter.generate_shop_markdown(shop_title, shop_items)
  end

  def generate_cshop_markdown(shop_symbol, shop_name, badges = 0)
    @shopGetter.generate_cshop_markdown(shop_symbol, shop_name, badges: badges)
  end

  def generate_move_markdown(move_name)
    # Creates nokogiri HTML
    m = @moveHash[move_name.to_sym]
    acc = m[:accuracy] == 0 ? "Perfect" : "#{m[:accuracy]}%"
    type = m[:type] == :QMARKS ? "???" : m[:type].to_s.capitalize
    "#{m[:name]}: #{type} \\| #{m[:category].to_s.capitalize} \\| #{m[:basedamage]} Pwr \\| #{acc} Acc \\| #{m[:desc]}"
  end

  def generate_trainer_markdown(trainer_id, field = nil)
    @trainerGetter.generate_trainer_markdown(trainer_id, field)
  end

  def generate_boss_markdown(boss_name, field = nil)
    @trainerGetter.generate_trainer_markdown(boss_name.to_sym, field)
  end

  def generate_battle_tower_singles_bosses_markdown
    return_array = []
    teams = { 'reborn' => REBORN_BT_SINGLES }[@game]
    teams.each do |team|
      field_name = FIELDS[team[3]]
      return_array.push(generate_trainer_markdown([team[1], team[0], team[2]], field_name))
    end
    return_array.join("\n\n")
  end

  def generate_battle_tower_doubles_bosses_markdown
    return_array = []
    teams = { 'reborn' => REBORN_BT_DOUBLES }[@game]
    teams.each do |team|
      field_name = FIELDS[team[3]]
      return_array.push(generate_trainer_markdown([team[1], team[0], team[2]], field_name))
    end
    return_array.join("\n\n")
  end

  def generate_theme_teams_markdown
    return_array = []
    teams = { 'reborn' => REBORN_THEME_TEAMS }[@game]
    teams.each do |team|
      fight, data = @trainerHash.find { |fight, _data| fight[0] == team[:trainer] && fight[2] == team[:teamnumber] }
      field_name = FIELDS[team[:field]]
      return_array.push(generate_bp_trainer_markdown(fight, field_name, team_name = "(#{team[:name]})"))
    end

    return_array.join("\n\n")
  end

  def generate_bp_trainer_markdown(trainer_id, field_text = 'Random Field', team_name = '')
    @trainerGetter.generate_trainer_markdown(trainer_id, field = field_text, nil, 0, name_ext = team_name)
  end

  def generate_double_markdown(trainer_id1, trainer_id2, field = nil)
    @trainerGetter.generate_trainer_markdown(trainer_id1, field, trainer_id2)
  end

  def generate_partner_markdown(trainer_id)
    @trainerGetter.generate_trainer_markdown(trainer_id, nil, nil, 1)
  end

  def generate_newself_markdown(trainer_id, new_title=nil)
    return @trainerGetter.generate_trainer_markdown(trainer_id, nil, nil, 2, new_title) if new_title
    return @trainerGetter.generate_trainer_markdown(trainer_id, nil, nil, 2)
  end

  def generate_tutor_markdown(tutor_title, moves)
    # Creates nokogiri HTML
    doc = Nokogiri::HTML::Document.new
    doc.encoding = 'UTF-8'
    div = doc.create_element('div', class: 'tutor_table')
    doc.add_child(div)

    table = doc.create_element('table')
    div.add_child(table)

    # Creates the header for the table
    thead = doc.create_element('thead')
    table.add_child(thead)

    table_header = doc.create_element('th', colspan: 2)
    thead.add_child(table_header)

    bold = doc.create_element('strong')
    bold.content = JaNames.shop(tutor_title)
    table_header.add_child(bold)
    table_header['class'] = 'table-header'
    table_header['style'] = 'text-align: center;'

    moves.each do |move, price|
      content_row = doc.create_element('tr')
      table.add_child(content_row)

      # Column 1: Move Name (bolded)
      td_move = doc.create_element('td', style: 'text-align: center')
      td_move.add_child(doc.create_element('strong', content = JaNames.tr('moves', move)))
      content_row.add_child(td_move)

      # Column 2: Price
      price = price.is_a?(Integer) ? "$#{price}" : JaNames.shard_cost(price)
      td_price = doc.create_element('td', style: 'text-align: center')
      td_price.content = price
      content_row.add_child(td_price)
    end

    html_output = doc.to_html(encoding: 'UTF-8')
    html_output.split("\n")[1..].join("\n")
  end

  def generate_raid_den_markdown(den_num, num_badges)
    res = []

    [:common, :rare].each do |rarity|

      # Create a Nokogiri document
      doc = Nokogiri::HTML::Document.new
      doc.encoding = 'UTF-8'
      div = doc.create_element('div', class: 'den_table')
      doc.add_child(div)
    
      table = doc.create_element('table')
      div.add_child(table)
    
      # Create the header for the table
      thead = doc.create_element('thead')
      table.add_child(thead)
    
      table_header = doc.create_element('th', colspan: 4)
      thead.add_child(table_header)

      # Header Row 2: Actual table headers
      thead_row = doc.create_element('tr')

      # Add table headers for Pokemon, Shadow Moves, Stat Details, and %
      ['Pokemon', 'Shadow Moves', 'Stat Details', 'Rate'].map { |c| JaNames.ui(c) }.each do |col|
        th = doc.create_element('th', col)
        th['style'] = 'text-align: center; vertical-align: middle;'
        thead_row.add_child(th)
      end

      thead.add_child(thead_row)  # Add the header row to thead
    
      bold = doc.create_element('strong')
      bold.content = "#{JaNames.ui('Encounters:')} Den \##{den_num} (#{num_badges} #{JaNames.ui('Badges')}): #{JaNames.ui(rarity.to_s.capitalize)}"
      table_header.add_child(bold)
      table_header['class'] = 'table-header'
      table_header['style'] = 'text-align: center;'
    
      # Create the body of the table
      tbody = doc.create_element('tbody')
      table.add_child(tbody)
    
      # Add encounters for common and rare
      @raidDenHash["Den#{den_num}"][rarity][num_badges].each do |mon, atts|
        content_row = doc.create_element('tr')
        tbody.add_child(content_row)

        # Use actual_pokemon key for pokemonHash lookup (handles form variants like GALARSTUNFISK -> STUNFISK)
        pokemon_lookup_key = atts[:actual_pokemon] || mon
        base_form = @pokemonHash[pokemon_lookup_key].keys.find_all { |key| key.is_a?(String) }[0]
        pokemon_name_formatted = @pokemonHash[pokemon_lookup_key][base_form][:name]

        if atts[:Form] != 0
          form_key = @pokemonHash[pokemon_lookup_key].keys.find_all { |key| key.is_a?(String) }[atts[:Form]]
          pokemon_name_formatted += " (#{JaNames.tr('form_names', form_key)})".sub(' Form', '')
        end
        pokemon_name_formatted = "#{JaNames.ui('Shadow ')}#{pokemon_name_formatted}"

        # Column 1: Pokémon Name & Details
        td_pokemon = doc.create_element('td')
        td_pokemon.add_child(doc.create_element('strong', pokemon_name_formatted))
        mon_details_parts = [", #{JaNames.ui('Lv.')} #{atts[:level]}"]
        if atts[:Ability] 
          mon_details_parts.push("Ability: #{atts[:Ability]}")
        end
        if atts[:ShinyChance] > 0 
          mon_details_parts.push("Shiny Chance Increase: #{atts[:ShinyChance] * 100}%")
        end
        td_pokemon.add_child(mon_details_parts.reject { |s| s.empty? }.join("\n"))
        content_row.add_child(td_pokemon)

        # Column 2: Movesets
        moves_edited = []
        atts[:Moves].each do |move|
          next if move == nil
          name = @moveHash[move][:name]
          moves_edited.push(name)
        end
        final = "- " + moves_edited.join("\n- ")
        if atts[:Moves] == []
          final = "N/A"
        end
        content_row.add_child(doc.create_element('td', final))

        # Column 3: Stat Attributes (e.g., Form, ShinyChance)
        td_attributes = doc.create_element('td')
        stat_details_parts = []
        if atts[:IVs] 
          stat_details_parts.push(get_iv_str(atts[:IVs]))
        end
        if atts[:EVs]
          stat_details_parts.push(get_ev_str(atts[:EVs]))
        end
        td_attributes.add_child(stat_details_parts.reject { |s| s.empty? }.join("\n"))
        content_row.add_child(td_attributes)
        
        # Column 4: Odds
        td_odds = doc.create_element('td')
        td_odds.add_child(sprintf('%.2f', atts[:odds]) + "%")
        content_row.add_child(td_odds)
      end
    
      # Convert to HTML and format
      html_output = doc.to_html(encoding: 'UTF-8')
      res.push(html_output.split("\n")[1..].join("\n"))
    end
    res = res.join("\n\n")
    res.gsub(/<td>\s*\n\s*<strong>/, '<td><strong>')
  end
end

def main
  fw = FunctionWrapper.new('reborn')
  # puts fw.generate_wild_held_markdown
end

main if __FILE__ == $PROGRAM_NAME
