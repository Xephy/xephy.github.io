require_relative 'common'
require_relative 'field_notes'
require_relative 'trainer_index'
require_relative 'field_usage'
require 'set'

class TrainerGetter
  attr_accessor :game, :trainer_hash, :trainer_type_hash, :item_hash, :move_hash, :ability_hash, :pokemon_hash, :stats


  def initialize(game, scripts_dir, trainer_hash = nil, boss_hash = nil, trainer_type_hash = nil, item_hash = nil, move_hash = nil, ability_hash = nil,
                 pokemon_hash = nil, type_hash = nil)
    @game = game
    # 元から @scriptsDir を読む箇所があったのに代入が無かった。フィールド効果
    # ページへのリンクを引くのにも要るので、ここで受け取っておく。
    @scriptsDir = scripts_dir
    @trainerHash = trainer_hash ||= load_trainer_hash(@game, @scriptsDir)
    @bossHash = boss_hash ||= load_boss_hash(@game, @scriptsDir)
    @trainerTypeHash = trainer_type_hash ||= load_trainer_type_hash(@game, @scriptsDir)
    @itemHash = item_hash ||= load_item_hash(@game, @scriptsDir)
    @moveHash = move_hash ||= load_move_hash(@game, @scriptsDir)
    @abilityHash = ability_hash ||= load_ability_hash(@game, @scriptsDir)
    @pokemonHash = pokemon_hash ||= load_pokemon_hash(@game, @scriptsDir)
    @typeHash = type_hash ||= load_type_hash(@game, @scriptsDir)
    @trainerStore = Set[]
    @stats = ["HP", "Atk", "Def", "SpA", "Spd", "Spe"]
  end

  # フィールド名を、資料ページ (/reborn/fields/) の該当節へのリンクにする。
  # ここは戦闘ごとに出る行で、実測で 471箇所ある。読者が「このフィールドは
  # 何をするのか」を知りたくなるのはまさにこの位置。
  #
  # 攻略側の表記はゲームの名前と綴りが揺れるので FieldNotes に解決させる。
  # 解けないもの (fork 独自の "Random Field") は素のテキストのまま出す。
  def field_node(doc, field)
    label = field ? JaNames.field(field) : JaNames.ui('No Field')
    key = field && FieldNotes.key_for(field, @scriptsDir)
    return doc.create_text_node(label) unless key

    # 逆向きの動線 (フィールド効果ページ -> 本文) 用に、使われた節を控える。
    FieldUsage.record(key)

    link = doc.create_element('a', class: 'field-link',
                                   href: "/#{LONGNAMES[@game]}/fields/##{FieldNotes.anchor(key)}")
    link.content = label
    link
  end

  def generate_trainer_markdown(trainer_id, field = nil, second_trainer_id = nil, type_mod = 0, name_ext = '')
    
    # a cursed workaround 
    if trainer_id.class == Array 
      trainer_id[0] = trainer_id[0].gsub("okemon", "okémon") # workaround for the cursed e character I can't just type
    end

    raise "Trainer ID #{trainer_id} not in Trainer Hash" unless (@trainerHash[trainer_id] || @bossHash[trainer_id])
    raise "Trainer ID #{second_trainer_id} not in Trainer Hash" if second_trainer_id && !@trainerHash[second_trainer_id]
    raise "Not a field - probably put trainer 2 in field arg: #{field}" if field && !field.index('[').nil?

    @trainerStore.add(trainer_id)
    @trainerStore.add(second_trainer_id) if second_trainer_id

    fight_is_boss = (trainer_id.class == Symbol)

    if !fight_is_boss
      trainer_data = @trainerHash[trainer_id]
      second_trainer_data = second_trainer_id ? @trainerHash[second_trainer_id] : nil
      trainer_name = JaNames.trainer_label(@trainerTypeHash[trainer_id[1]][:title], trainer_id[0])
      trainer_name += " #{name_ext}" unless name_ext.nil?
      second_trainer_name = second_trainer_id ? JaNames.trainer_label(@trainerTypeHash[second_trainer_id[1]][:title], second_trainer_id[0]) : nil
    else
      trainer_data = @bossHash[trainer_id]
      trainer_name = trainer_data[:name]
      second_trainer_name = nil
      boss_data = trainer_data
    end
    shield_break_details = []


    # Handles trainers with :baseTeam attr. Reuses one trainer data while allowing changes like
    # same team fight across routes with diff dialogue, etc. 
    # See `if trainer[:baseTeam]` branch on DataObjects - Compilers
    if trainer_data[:baseTeam]
      base_trainer_data = @trainerHash.fetch(trainer_data[:baseTeam])
      trainer_data = base_trainer_data.merge(trainer_data)
    end

    item_symbols = Hash.new(0)
    item_symbols.merge!(trainer_data[:items].tally) if trainer_data[:items]

    if second_trainer_id && second_trainer_data && second_trainer_data[:items]
      second_trainer_data[:items].tally.each do |item, count|
        item_symbols[item] += count
      end
    end

    # Some trainers have delayed actions here TODO
    if trainer_data[:delayedactions]
      # pp trainer_data[:delayedactions]
    end

    # Creates nokogiri HTML
    doc = Nokogiri::HTML::Document.new
    doc.encoding = 'UTF-8'
    div = doc.create_element('div', class: 'trainer_section')
    doc.add_child(div)

    table = doc.create_element('table')
    div.add_child(table)

    # Creates the header for the table
    table_header = doc.create_element('thead')
    table_header['class'] = 'table-header'
    table.add_child(table_header)

    # Header Row 1: Trainer Names, Field, Items
    thead_row = doc.create_element('tr')
    table_header.add_child(thead_row)

    th = doc.create_element('th', colspan: 3, class: 'header-th')

    # First TD for main content (VS, Field, Items)
    td_main_content = doc.create_element('div')

    bold = doc.create_element('strong')
    bold.content =  if fight_is_boss
                      "VS #{JaNames.ui('Boss ').strip}: #{trainer_name}"
                    elsif second_trainer_name
                      "#{JaNames.ui('VS:')} #{trainer_name} & #{second_trainer_name}"
                    elsif type_mod == 0
                      "#{JaNames.ui('VS:')} #{trainer_name}"
                    elsif type_mod == 1
                      "#{JaNames.ui('Partner:')} #{trainer_name}"
                    elsif type_mod == 2
                      "POV Trainer: #{name_ext != "" ? name_ext : trainer_name}"
                    end

    td_main_content.add_child(bold)

    if type_mod == 0 # we don't need field for partners or selves
      field_div = doc.create_element('div')
      field_div.content = "#{JaNames.ui('Field:')} "
      td_main_content.add_child(field_div)
      field_div.add_child(field_node(doc, field))
    end

    if type_mod == 0 && !item_symbols.empty? # Adds count of enemy trainer items
      item_str = item_symbols.map { |sym, count| "#{@itemHash[sym][:name]}#{count > 1 ? " (#{count})" : ''}" }
      items_div = doc.create_element('div')
      items_div.content = "#{JaNames.ui('Items:')} #{item_str.join(', ')}"
      td_main_content.add_child(items_div)
    end

    th.add_child(td_main_content)

    # Second TD for [show] or [hide] text
    td_show_hide = doc.create_element('div', class: 'show-hide-container') # style: 'text-align: right;')
    # span のままだとキーボードでたどり着けないので、押せるものとして扱わせる。
    show_hide_text = doc.create_element('span', class: 'show-hide-text', style: 'cursor: pointer;',
                                                role: 'button', tabindex: '0')
    show_hide_text.content = JaNames.ui('[show]')
    # 開閉時のラベルは JavaScript 側で差し替わる。訳語の管理を _ja/ui.yml に
    # 一本化するため、文字列は data 属性で渡す。
    show_hide_text['data-show'] = JaNames.ui('[show]')
    show_hide_text['data-hide'] = JaNames.ui('[hide]')
    td_show_hide.add_child(show_hide_text)

    th.add_child(td_show_hide)

    thead_row.add_child(th)

    # Header Row 2: Actual table headers
    thead_row = doc.create_element('tr')

    ['Pokemon', 'Moves', 'Stat Info'].map { |c| JaNames.ui(c) }.each do |col|
      thead_row.add_child(doc.create_element('th', col, style: 'text-align: center;vertical-align : middle'))
    end
    table_header.add_child(thead_row)

    # Trainer Mon data
    if fight_is_boss
      list_of_mons = [trainer_data[:moninfo]] + (trainer_data[:sosDetails] ? trainer_data[:sosDetails][:moninfos].values : [])
    else
      list_of_mons = trainer_data[:mons] + (second_trainer_data ? second_trainer_data[:mons] : [])
    end

    list_of_mons.each_with_index do |mon, idx|
      content_row = doc.create_element('tr')
      table.add_child(content_row)

      if mon[:boss] # Here we handle some overrides for boss mons in otherwise normal teams....
        boss_data = @bossHash[mon[:boss]]
        # Override whatever junk is in the trainer file, if its a boss
        mon[:species] = boss_data[:moninfo][:species] if boss_data[:moninfo][:species]
        mon[:moves] = boss_data[:moninfo][:moves] if boss_data[:moninfo][:moves]
        mon[:ability] = boss_data[:moninfo][:ability] if boss_data[:moninfo][:ability]
        mon[:iv] = boss_data[:moninfo][:iv] if boss_data[:moninfo][:iv]
        mon[:ev] = boss_data[:moninfo][:ev] if boss_data[:moninfo][:ev]
        mon[:nature] = boss_data[:moninfo][:nature] if boss_data[:moninfo][:nature]
        mon[:level] = boss_data[:moninfo][:level] if boss_data[:moninfo][:level]
        mon[:form] = boss_data[:moninfo][:form] if boss_data[:moninfo][:form]
        mon[:item] = boss_data[:moninfo][:item] if boss_data[:moninfo][:item]
      end

      if fight_is_boss && idx == 0
        mon[:boss] = true
      elsif fight_is_boss
        mon[:sos] = true
      end

      # See if there is :delayedactions on either the trainer team or the boss. Maybe combine two lists? TODO

      form = mon[:form] || 0
      form_key = @pokemonHash[mon[:species]].keys.find_all { |key| key.is_a?(String) }[form]
      form_data = @pokemonHash[mon[:species]][form_key]

      form_1_key = @pokemonHash[mon[:species]].keys.find_all { |key| key.is_a?(String) }[0]
      form_1_data = @pokemonHash[mon[:species]][form_1_key]

      # This handles the strange case of Minior having its data in Meteor Form instead of Red, but Meteor Form at the end...
      if form_1_data[:baseForm]
        bfData = @pokemonHash[mon[:species]][form_1_data[:baseForm]]
        bfData.each do |k, v|
          if form_1_data[k] == nil
            form_1_data[k] = v
          end
        end
      end

      pokemon_name = "#{mon[:shadow] ? JaNames.ui("Shadow ") : ""}#{@pokemonHash[mon[:species]][form_1_key][:name]}"
      if fight_is_boss || mon[:boss]
        pokemon_name = "#{mon[:boss] ? JaNames.ui("Boss ") : JaNames.ui("SOS ")}#{pokemon_name}"
      end

      # 「このポケモンを使うトレーナーは誰か」の逆引き。ポケモン個別ページが使う。
      # 表を組んでいるこの場で拾うので、画面に出る手持ちと数が食い違わない。
      TrainerIndex.record(species: mon[:species], form: form, level: mon[:level],
                          trainer: trainer_name)

      # Some mons, like alt color Joltik, are custom forms without form data...
      if form_key == nil 
        form_key = form_1_key
        form_data = form_1_data
      end

      base_stats = form_data[:BaseStats] ? form_data[:BaseStats] : form_1_data[:BaseStats]
      
      if mon[:ability]
        abText = @abilityHash[mon[:ability]][:name]
      else
        abs = form_data[:Abilities] ? form_data[:Abilities] : form_1_data[:Abilities]
        abText = abs.map {|a| @abilityHash[a][:name]}.join("/")
      end

      # 性別とレベルは名前のすぐ横に置く。1つの塊として扱わないと、
      # 列が狭いときに "Lv." と数字が別の行に割れてしまう。
      mon_meta = [
        mon[:gender] ? JaNames.ui(mon[:gender].to_s) : nil,
        "#{JaNames.ui('Lv.')}#{mon[:level]}"
      ].compact.join(' ')

      # 以降は1行1項目。ラベルを付けて行頭を揃える。
      mon_details_parts = [
        "#{form > 0 ? JaNames.tr('form_names', @pokemonHash[mon[:species]].keys.find_all { |key| key.is_a?(String) }[mon[:form]]) : ''}",
        "#{mon[:item] ? "#{JaNames.ui('Held item:')} #{@itemHash[mon[:item]][:name]}" : ''}",
        "#{JaNames.ui('Ability:')} #{abText}"
      ]

      custom_form_bool = is_custom_form(form_key)

      if custom_form_bool # Add typing only for custom formes
        type1 = form_data[:Type1] ? @typeHash[form_data[:Type1]][:name] : @typeHash[form_1_data[:Type1]][:name]
        type2 = form_data[:Type2] ? @typeHash[form_data[:Type2]][:name] : (form_1_data[:Type2] ? @typeHash[form_1_data[:Type2]][:name] : nil)
        if type2.nil? || type1 == type2
          typeStr = "#{JaNames.ui('Typing:')} #{type1}"
        else
          typeStr = "#{JaNames.ui('Typing:')} #{type1}/#{type2}"
        end
        mon_details_parts.push(typeStr)
      end

      # Handles display of SOS Mons for full-boss fights
      if mon[:sos]
        oper, shields = boss_data[:sosDetails][:activationRequirement].split(" ").slice(1,2)
        refresh = boss_data[:sosDetails][:refreshingRequirement]
        cont = boss_data[:sosDetails][:continuous] != nil
        shield_text = case oper
          when "<" then "Less than #{shields} Shield(s)"
          when "<=" then "Less than #{shields.to_i + 1} Shield(s)"
          when "==" then "Exactly #{shields} Shield(s)"
        end
        mon_details_parts.push("Appears: #{shield_text} #{cont ? " (Continuous)" : ""}")
        mon_details_parts.push("Refreshes when boss @ #{refresh.join(", ")} shields") if refresh
      end        
      
      # Handles display of boss mon - including shield info
      if mon[:boss]
        boss_data[:onBreakEffects] ||= {}

        # Workaround for onEntryEffects note "100 shields"
        if boss_data[:onEntryEffects] && boss_data[:onEntryEffects].keys != [:message]
          boss_data[:onBreakEffects][100] = boss_data[:onEntryEffects]
        end

        # Handles text parts of boss data
        mon_details_parts.push("Shields: #{boss_data[:shieldCount]}")
        if boss_data[:immunities] != {}
          if boss_data[:immunities][:moves] && boss_data[:immunities][:moves] != []
            mon_details_parts.push("Immunities to moves: #{boss_data[:immunities][:moves].join(", ")}") 
          end
          if boss_data[:immunities][:fieldEffectDamage] && boss_data[:immunities][:fieldEffectDamage] != []
            fields = boss_data[:immunities][:fieldEffectDamage].map {|f| FIELDS[f]}
            mon_details_parts.push("Immunities to field damage: #{fields.join(", ")}") 
          end
        end
        sorted_keys = boss_data[:onBreakEffects].keys.sort_by do |key|
          key >= 0 ? [-1, -key] : [1, key]
        end
        sorted_keys.each do |shield_count|
          effs = boss_data[:onBreakEffects][shield_count]         
          if shield_count == 100
            result = "On Entry: \n"  
          else
            threshold_text = "#{effs[:threshold] != 0 ? " (Regenerates Shield Infinitely)" : ""}"
            result = "Shield Break #{shield_count}#{threshold_text}: \n"  
          end

          eff_strs = []
          if effs[:bossEffect]
            eff_strs.push("Effect added to boss's side: #{effs[:bossEffect].to_s.gsub(/([a-z])([A-Z])/, '\1 \2')}") 
          end
          if effs.key?(:weatherChange)
            if effs[:weatherChange] == nil
              eff_strs.push("Weather is nullified")
            else
              # Weather move, num turns (-1 = indefinite), message
              moveS, turns, message = effs[:weatherChange]   
              move = @moveHash[moveS]
              if @moveHash[moveS]
                weatherName = @moveHash[moveS][:name]
              elsif moveS == :STRONGWINDS
                weatherName = "Strong Winds"
              elsif moveS == :SUNNY
                weatherName = "Sunny Day"
              elsif moveS == :RAIN
                weatherName = "Rain Dance"
              else
                raise "Weather missing: #{moveS}"
              end

              if turns == -1 
                eff_strs.push("Weather becomes #{weatherName} indefinitely")
              else
                eff_strs.push("Weather becomes #{weatherName} for #{turns} turns")
              end
            end
          end
          if effs[:speciesUpdate]
            if effs[:speciesUpdate].is_a?(Array)
              monKey = effs[:speciesUpdate][0]
              form = effs[:speciesUpdate][1]
            else
              monKey = effs[:speciesUpdate]
              form = 0 # todo maybe?
            end
            formKey = @pokemonHash[monKey].to_a[form][0]
            if formKey != "Normal Form"
              eff_strs.push("Boss becomes #{@pokemonHash[monKey][@pokemonHash[monKey].to_a[0][0]][:name]} (#{JaNames.tr('form_names', formKey)})")
            else
              eff_strs.push("Boss becomes #{@pokemonHash[monKey][formKey][:name]}")
            end
            mon[:species] = monKey # mutation... we'll see if this works.
          end

          if effs[:formchange]
            new_form = effs[:formchange]
            new_form_key = @pokemonHash[mon[:species]].keys.find_all { |key| key.is_a?(String) }[new_form]
            new_form_data = @pokemonHash[mon[:species]][new_form_key]

            form_changes = []

            if is_custom_form(form_key)

              new_type1 = new_form_data[:Type1] ? @typeHash[new_form_data[:Type1]][:name] : nil
              new_type2 = new_form_data[:Type2] ? @typeHash[new_form_data[:Type2]][:name] : (form_1_data[:Type2] ?  @typeHash[form_1_data[:Type2]][:name] : nil)
              types = [new_type1, new_type2].compact
              if !new_type1 || (type1 != new_type1 || type2 != new_type2)
                form_changes.push("Typing => #{types.join("/")}")
              end

              new_base_stats = new_form_data[:BaseStats] ? new_form_data[:BaseStats] : form_1_data[:BaseStats]
              if new_base_stats != base_stats
                form_changes.push('Base Stats => ' + new_base_stats.zip(EV_ARRAY).map { |stat, position| "#{stat} #{position}" }.join(', '))
              end
              eff_strs.push("Form changes to #{new_form_key} (#{form_changes.join('; ')})") 
            else
              eff_strs.push("Form changes to #{new_form_key}") 
            end
          end
          if effs[:fieldChange]
            eff_strs.push("Field becomes #{FIELDS[effs[:fieldChange]]}") 
          end
          if effs[:abilitychange]
            eff_strs.push("Boss's ability becomes #{@abilityHash[effs[:abilitychange]][:name]}") 
          end
          if effs[:typeChange]
            eff_strs.push("Boss's type becomes #{effs[:typeChange].map {|type| @typeHash[type][:name]}.join("/")}")
          end
          if effs[:movesetUpdate]
            eff_strs.push("Boss's moveset becomes #{effs[:movesetUpdate].compact.map{|m|@moveHash[m][:name]}.join(', ')}")
          end
          if effs[:statDropRefresh]
            eff_strs.push("Boss's stat changes are reset")
          end
          if effs[:statusCure]
            eff_strs.push("Boss's status effects cured") 
          end
          if effs[:effectClear]
            eff_strs.push("Effects are cleared") 
          end
          if effs[:bossSideStatusChanges]
            eff_strs.push("Effect added to boss's side: #{effs[:bossSideStatusChanges].to_s.gsub(/([a-z])([A-Z])/, '\1 \2')}") 
          end
          if effs[:playerSideStatusChanges]
            eff_strs.push("Status added to player's side: #{effs[:playerSideStatusChanges][1].to_s.gsub(/([a-z])([A-Z])/, '\1 \2')}")
          end
          if effs[:statDropCure]
            eff_strs.push("Boss's stat drops are cured")
          end
          if effs[:playerEffects]
            eff_strs.push("Effect added to player's side: #{effs[:playerEffects].to_s.gsub(/([a-z])([A-Z])/, '\1 \2')}") 
          end
          if effs[:stateChanges]
            eff_strs.push("Effect added to battle: #{effs[:stateChanges].to_s.gsub(/([a-z])([A-Z])/, '\1 \2')}")
          end
          if effs[:playersideChanges]
            if effs[:playersideChanges].class == Array
              eff_strs.push("Effects added to player side: #{effs[:playersideChanges].join(', ').gsub(/([a-z])([A-Z])/, '\1 \2')}") 
            else
              eff_strs.push("Effect added to player side: #{effs[:playersideChanges].to_s.gsub(/([a-z])([A-Z])/, '\1 \2')}") 
            end
          end
          if effs[:bosssideChanges]
            if effs[:bosssideChanges].class == Array
              eff_strs.push("Effects added to boss's side: #{effs[:bosssideChanges].join(', ').gsub(/([a-z])([A-Z])/, '\1 \2')}") 
            else
              eff_strs.push("Effect added to boss's side: #{effs[:bosssideChanges].to_s.gsub(/([a-z])([A-Z])/, '\1 \2')}") 
            end
          end
          if effs[:itemchange]
            eff_strs.push("Boss's held item becomes #{@itemHash[effs[:itemchange]][:name]}")
          end
          if effs[:bossStatChanges]
            groups = {}
            effs[:bossStatChanges].each do |stat, lvl|
              groups[lvl] ||= []
              groups[lvl].push(stat)
            end
            groups.each do |lvl, stats|
              eff_strs.push("Boss's #{stats.join(', ')} stat#{stats.length == 1 ? "" : "s"} #{lvl > 0 ? "raised" : "lowered"} #{lvl.abs} stage#{lvl.abs == 1 ? "" : "s"}")
            end
          end
          if effs[:playerSideStatChanges]
            groups = {}
            effs[:playerSideStatChanges].each do |stat, lvl|
              groups[lvl] ||= []
              groups[lvl].push(stat)
            end
            groups.each do |lvl, stats|
              eff_strs.push("Player's #{stats.join(', ')} stat#{stats.length == 1 ? "" : "s"} #{lvl > 0 ? "raised" : "lowered"} #{lvl.abs} stage#{lvl.abs == 1 ? "" : "s"}")
            end
          end
          if effs[:CustomMethod] && effs[:CustomMethod].match(/^battlesnapshot/)
            eff_strs.push("A snapshot in time is taken...")
          end
          if effs[:CustomMethod] && effs[:CustomMethod].match(/^timewarp/)
            eff_strs.push("A timewarp to the last snapshot occurs...")
          end
          # The bosses enqueue certain delayed actions upon shield break, or there's some trigger condition (see :queuedelays) TODO

          # The way delayed effects work is... janky. In any case I will deal with it here.
          if effs[:delayedaction]
            actions = []
            tc = 0
            curr = effs[:delayedaction]
            while curr
              tc += curr[:delay]
              actions.push([tc, curr])
              curr = curr[:delayedaction]
            end
            actions.each do |tc, act|
              if act[:repeat] && !act[:typeSequence]
                ts = "After every #{tc} turn#{tc == 1 ? "" : "s"}: "
              else
                ts = "After #{tc} turn#{tc == 1 ? "" : "s"}: "
              end
              if act[:fieldChange]
                eff_strs.push("#{ts}Field becomes #{FIELDS[act[:fieldChange]]}") 
              end
              if act[:playerSideStatChanges]
                groups = {}
                act[:playerSideStatChanges].each do |stat, lvl|
                  groups[lvl] ||= []
                  groups[lvl].push(stat)
                end
                groups.each do |lvl, stats|
                  eff_strs.push("#{ts}Player's #{stats.join(', ')} stat#{stats.length == 1 ? "" : "s"} #{lvl > 0 ? "raised" : "lowered"} #{lvl.abs} stage#{lvl.abs == 1 ? "" : "s"}")
                end
              end
              if act[:playerSideStatusChanges]
                eff_strs.push("#{ts}Status added to player's side: #{act[:playerSideStatusChanges][1].to_s.gsub(/([a-z])([A-Z])/, '\1 \2')}")
              end
              if act[:playerEffects]
                if act[:playerEffects] == [:FutureSight,:FutureSightMove]
                  turns, move = act[:playerEffectsduration]
                  eff_strs.push("#{ts}Effect added to player's side: #{@moveHash[move][:name]} impacting in #{turns} turns") 
                elsif act[:playerEffects].class == Array
                  eff_strs.push("#{ts}Effects added to player side: #{act[:playerEffects][0].to_s.gsub(/([a-z])([A-Z])/, '\1 \2')}") 
                else
                  eff_strs.push("#{ts}Effect added to player side: #{act[:playerEffects].to_s.gsub(/([a-z])([A-Z])/, '\1 \2')}") 
                end
              end
              if act[:bossStatChanges] 
                groups = {}
                act[:bossStatChanges].each do |stat, lvl|
                  groups[lvl] ||= []
                  groups[lvl].push(stat)
                end
                groups.each do |lvl, stats|
                  eff_strs.push("#{ts}Boss's #{stats.join(', ')} stat#{stats.length == 1 ? "" : "s"} #{lvl > 0 ? "raised" : "lowered"} #{lvl.abs} stage#{lvl.abs == 1 ? "" : "s"}")
                end
              end
              if act[:bossEffect]
                eff_strs.push("#{ts}Effect added to boss's side: #{act[:bossEffect].to_s.gsub(/([a-z])([A-Z])/, '\1 \2')}") 
              end

              if act[:typeSequence]
                typeCycles = []
                act[:typeSequence].each do |num, obj|
                  typeCycles.push(obj[:typeChange].map {|type| @typeHash[type][:name]}.uniq.join("/"))
                end
                eff_strs.push("#{ts}Begins cycling types each turn: #{typeCycles.join(" -> ")}")
              end
              if act[:CustomMethod] && act[:CustomMethod].match(/^battlesnapshot/)
                eff_strs.push("#{ts}A snapshot in time is taken...")
              end
              if act[:CustomMethod] && act[:CustomMethod].match(/^timewarp/)
                eff_strs.push("#{ts}A timewarp to the last snapshot occurs...")
              end
            end
          end
          result += "- #{eff_strs.join("\n- ")}"
          shield_break_details.push(result)
        end
      end

      # Trainer Data and party size offset
      trainer_effects = [[trainer_data[:trainereffect], 0]]
      if second_trainer_data
        trainer_effects.push([second_trainer_data[:trainereffect], trainer_data[:mons].length])
      end
      trainer_effects.each do |trainerEffect, offset|
        next if trainerEffect == nil
        next if ![:Party].include?(trainerEffect[:effectmode])
        if trainerEffect[idx - offset]
          effs = trainerEffect[idx - offset]
          if effs[:pokemonStatChanges]
            groups = {}
            effs[:pokemonStatChanges].each do |stat, lvl|
              groups[lvl] ||= []
              groups[lvl].push(stat)
            end
            if groups != {}
              groups.each do |lvl, indices|
                statNames = indices.map { |idx| stats[idx] }
                mon_details_parts.push("#{statNames.join(', ')} stat#{stats.length == 1 ? "" : "s"} #{lvl > 0 ? "raised" : "lowered"} #{lvl.abs} stage#{lvl.abs == 1 ? "" : "s"}")
              end
            end
          end
          if effs[:instantMove]
            m = effs[:instantMove][0]
            mon_details_parts.push("Instantly uses #{@moveHash[m][:name]}")
          end
          if effs[:fieldChange]
            field = FIELDS[effs[:fieldChange][0].to_sym]
            mon_details_parts.push("Field changes to #{field}")
          end
          if effs[:pokemonEffect]
            effs[:pokemonEffect].each do |eff, _arr|
              eff = eff.to_s.gsub(/([a-z])([A-Z])/, '\1 \2')
              mon_details_parts.push("Effect applied: #{eff}")
            end
          end
          if effs[:typeChange]
            mon_details_parts.push("Typing changed to: #{effs[:typeChange].map {|type| @typeHash[type][:name]}.join("/")}")
          end
          if effs[:trainersideChanges]
            mon_details_parts.push("Effects added to trainer's side: #{effs[:trainersideChanges].keys.map{|k| k.to_s}.join(", ").gsub(/([a-z])([A-Z])/, '\1 \2')}") 
          end
        end
      end

      mon_details_td = doc.create_element('td')
      mon_details_td['class'] = 'mon-cell'

      head = doc.create_element('div')
      head['class'] = 'mon-head'

      # 種族のアイコン。bin/gen-mon-icons がゲームのシートから切り出したもの。
      # 1ページに数百個並ぶので loading="lazy" で画面に入るまで読ませない。
      # アイコンと名前はポケモン個別ページへの入口にする。本文の表は
      # 「このトレーナーが何を使うか」しか答えないので、その種族について
      # 知りたくなったときの行き先をここに置く。
      mon_href = mon_page_href(@game, mon[:species])

      icon_src = mon_icon_src(mon[:species], form)
      if icon_src
        icon = doc.create_element('img')
        icon['src'] = icon_src
        icon['alt'] = ''            # 名前がすぐ隣にあるので読み上げは不要
        icon['class'] = 'mon-icon'
        icon['loading'] = 'lazy'
        icon['width'] = '48'
        icon['height'] = '48'
        icon_link = doc.create_element('a', href: mon_href, class: 'mon-link')
        icon_link.add_child(icon)
        head.add_child(icon_link)
      end

      ident = doc.create_element('div')
      ident['class'] = 'mon-id'
      name_el = doc.create_element('strong', pokemon_name)
      name_el['class'] = 'mon-name'
      name_link = doc.create_element('a', href: mon_href, class: 'mon-link')
      name_link.add_child(name_el)
      ident.add_child(name_link)
      meta_el = doc.create_element('span', mon_meta)
      meta_el['class'] = 'mon-meta'
      ident.add_child(meta_el)
      head.add_child(ident)
      mon_details_td.add_child(head)

      props = mon_details_parts.reject { |s| s.to_s.strip.empty? }
      unless props.empty?
        props_el = doc.create_element('div')
        props_el['class'] = 'mon-props'
        props.each { |line| props_el.add_child(doc.create_element('div', line)) }
        mon_details_td.add_child(props_el)
      end
      content_row.add_child(mon_details_td)

      # Create list of default moves
      unless mon[:moves]
        mon[:moves] = []
        moveset = form_data[:Moveset] || form_1_data[:Moveset]
        movelist = []
        if moveset == nil
          pp form_data
          pp form_1_data
          raise "No moveset for #{mon[:species]} (#{form_key})"
        end
        for i in moveset
          movelist.push(i[1]) if i[0] <= mon[:level]
        end
        movelist |= [] # Remove duplicates
        listend = movelist.length - 4
        listend = 0 if listend < 0
        for i in listend...listend + 4
          next if i >= movelist.length

          mon[:moves].push(movelist[i])
        end
      end

      if mon[:boss] && boss_data[:chargeAttack]
        mon[:moves].push(boss_data[:chargeAttack][:intermediateattack]) if boss_data[:chargeAttack][:intermediateattack]
        mon[:moves].push(boss_data[:chargeAttack])
      end

      # わざは名前だけだと相性が判断できないので、タイプ・分類・威力を添える。
      # データは movetext.rb に揃っているので、追加の素材は要らない。
      moves_td = doc.create_element('td')
      moves_ul = doc.create_element('ul')
      moves_ul['class'] = 'move-list'
      moves_td.add_child(moves_ul)

      mon[:moves].each do |move|
        next if move == nil

        move_data = nil
        if move.class == Hash
          if move[:turns] # is a charge attack
            name = "#{JaNames.ui('Charge Attack')} (#{move[:turns]}#{JaNames.ui(' turns')})"
          else # is an intermediate attack
            name = "#{move[:name]} (#{JaNames.ui('Intermediate attack')})"
          end
        else
          move_data = @moveHash[move]
          name = move_data[:name]
        end
        name = name + hp_str(name, mon[:hptype])

        li = doc.create_element('li')
        li['class'] = 'move'

        if move_data
          # "めざめるパワー (ほのお)" のように、わざ側でタイプが変わる表記が
          # ある。その場合は括弧の中を優先して色を決める。
          type_sym = hp_type_override(name) || move_data[:type]
          type_name = type_sym && @typeHash[type_sym] ? @typeHash[type_sym][:name] : nil
          if type_name
            badge = doc.create_element('span', type_name)
            badge['class'] = "type-badge type-#{type_sym.to_s.downcase}"
            li.add_child(badge)
          end
        end

        name_span = doc.create_element('span', name)
        name_span['class'] = 'move-name'
        # 効果はパッチの説明文をそのまま出す。title 属性なので画像も JS も要らない。
        if move_data && move_data[:desc] && !move_data[:desc].to_s.empty?
          name_span['title'] = move_desc_tooltip(move_data)
        end
        li.add_child(name_span)

        if move_data
          # 分類・威力・命中を固定幅の3枠で出す。命中はバトル中に真っ先に
          # 知りたい値なので、説明の中ではなく常に見える位置に置く。
          meta_span = doc.create_element('span')
          meta_span['class'] = 'move-meta'

          cat = doc.create_element('span', JaNames.ui(move_data[:category].to_s))
          cat['class'] = 'move-cat'
          meta_span.add_child(cat)

          power = move_data[:basedamage].to_i
          pw = doc.create_element('span', power.positive? ? power.to_s : '—')
          pw['class'] = 'move-power'
          meta_span.add_child(pw)

          acc = move_data[:accuracy].to_i
          ac = doc.create_element('span', acc.zero? ? JaNames.ui('never misses') : "#{acc}%")
          ac['class'] = acc.zero? ? 'move-acc is-sure' : 'move-acc'
          meta_span.add_child(ac)

          li.add_child(meta_span)
        end

        moves_ul.add_child(li)
      end
      content_row.add_child(moves_td)

      # Handles stats next: base stats if applicable, IVs, Nature, EVs
      stat_details_parts = []
      if custom_form_bool # Only add base stats when custom form
        base_stats_str = JaNames.ui('Base Stats:') + ' ' + base_stats.zip(EV_ARRAY).map { |stat, position| "#{stat} #{position}" }.join(', ')
        stat_details_parts.push(base_stats_str) 
      end
      # 性格は naturetext.rb ではなくシンボルを capitalize して作られる (:TIMID -> "Timid")。
      nature = (mon[:nature] || :HARDY).capitalize.to_s
      stat_details_parts.push("#{JaNames.ui('Nature')}: #{JaNames.tr('natures', nature)}")

      stat_details_parts.push(get_ev_str(mon[:ev], mon[:level]))
      stat_details_parts.push(get_iv_str(mon[:iv]))
      stat_details_td = doc.create_element('td', stat_details_parts.join("\n"))
      content_row.add_child(stat_details_td)

      # Adds Shield Break Details to the end
      if shield_break_details != []
        shield_break_row = doc.create_element('tr')
        table.add_child(shield_break_row)

        shield_break_td = doc.create_element('td', colspan: 3)
        shield_break_td.add_child(shield_break_details.reject { |s| s.empty? }.join("\n"))
        shield_break_row.add_child(shield_break_td)

        shield_break_details = []
      end
    end

    # TrainerEffects that are not party based
    if trainer_data[:trainereffect] && trainer_data[:trainereffect][:effectmode] == :Fainted
      teff_details = []
      teff = trainer_data[:trainereffect]
      (1..6).each do |idx|
        fs = "After #{idx} Pokemon have fainted: "
        next if !teff[idx]
        effs = teff[idx]
        if effs[:fieldChange]
          field = FIELDS[effs[:fieldChange][0].to_sym]
          teff_details.push("#{fs}Field changes to #{field}")
        end
        if effs[:delayedaction]
          actions = []
          tc = 0
          curr = effs[:delayedaction]
          while curr
            tc += curr[:delay]
            actions.push([tc, curr])
            curr = curr[:delayedaction]
          end
          actions.each do |tc, act|
            if act[:repeat] && !act[:typeSequence]
              ts = "After every #{tc} turn#{tc == 1 ? "" : "s"}: "
            else
              ts = "After #{tc} turn#{tc == 1 ? "" : "s"}: "
            end
            if act[:fieldChange]
              field = FIELDS[act[:fieldChange][0].to_sym]
              teff_details.push("#{ts}Field changes to #{field}")
            end
            if act[:playerSideStatChanges]
              groups = {}
              act[:playerSideStatChanges].each do |stat, lvl|
                groups[lvl] ||= []
                groups[lvl].push(stat)
              end
              groups.each do |lvl, stats|
                teff_details.push("#{ts}Player's #{stats.join(', ')} stat#{stats.length == 1 ? "" : "s"} #{lvl > 0 ? "raised" : "lowered"} #{lvl.abs} stage#{lvl.abs == 1 ? "" : "s"}")
              end
            end
            if act[:playerSideStatusChanges]
              teff_details.push("#{ts}Status added to player's side: #{act[:playerSideStatusChanges][1].to_s.gsub(/([a-z])([A-Z])/, '\1 \2')}")
            end
            if act[:playerEffects]
              teff_details.push("#{ts}Effect added to player's side: #{act[:playerEffects].to_s.gsub(/([a-z])([A-Z])/, '\1 \2')}") 
            end
            if act[:bossStatChanges] 
              groups = {}
              act[:bossStatChanges].each do |stat, lvl|
                groups[lvl] ||= []
                groups[lvl].push(stat)
              end
              groups.each do |lvl, stats|
                teff_details.push("#{ts}Boss's #{stats.join(', ')} stat#{stats.length == 1 ? "" : "s"} #{lvl > 0 ? "raised" : "lowered"} #{lvl.abs} stage#{lvl.abs == 1 ? "" : "s"}")
              end
            end
            if act[:bossEffect]
              teff_details.push("#{ts}Effect added to boss's side: #{act[:bossEffect].to_s.gsub(/([a-z])([A-Z])/, '\1 \2')}") 
            end
            if act[:typeSequence]
              typeCycles = []
              act[:typeSequence].each do |num, obj|
                typeCycles.push(obj[:typeChange].map {|type| @typeHash[type][:name]}.uniq.join("/"))
              end
              teff_details.push("#{ts}Begins cycling types each turn: #{typeCycles.join(" -> ")}")
            end
          end
        end
      end

      teff_row = doc.create_element('tr')
      table.add_child(teff_row)
      teff_td = doc.create_element('td', colspan: 3)
      teff_td.add_child(teff_details.reject { |s| s.empty? }.join("\n-> "))
      teff_row.add_child(teff_td)
    end 

    doc.to_html(encoding: 'UTF-8').gsub(/<td>\s*\n\s*<strong>/, '<td><strong>').split("\n")[1..].join("\n")
  end

  def report_missing_trainers
    puts 'UNUSED TRAINER IDs: '
    @trainerHash.each do |trainer_id, _data|
      next if @trainerStore.include?(trainer_id)
      p trainer_id
    end
  end
end

def main
  e = TrainerGetter.new('reborn')
  puts e.generate_trainer_markdown(["Ace of Clubs", :ACECLUBS, 0])
  # puts e.generate_trainer_markdown(['Cain', :Cain, 5], 'Chess Board')
  # puts e.generate_trainer_markdown(["Arlo", :SWIMMERBOI, 0])
  # puts e.generate_trainer_markdown(["Yan", :TechNerd, 0])
  # puts e.generate_trainer_markdown(["Jackson", :COOLTRAINER_Male, 0], nil, ["Mack", :StreetRat, 0])
  # puts e.generate_trainer_markdown(["Aster", :AsterKnight, 0], nil, ["Eclipse", :EclipseDame, 0])
end

main if __FILE__ == $PROGRAM_NAME
