# frozen_string_literal: true

require 'json'
require 'yaml'

# 日本語化パッチが書き出した辞書 (_ja/dict.json) を読み、ゲームデータ由来の
# 固有名詞を日本語に差し替える。
#
# 差し替えは2系統ある。混ぜると壊れるので分けてある。
#
#   1. ロード直後のハッシュを書き換える (localize_* 系)
#      montext / itemtext / movetext などの :name :desc :title は、生成側の
#      40箇所以上から読まれている。ハッシュを1回書き換えれば全部に効くので、
#      呼び出し側には手を入れない。
#
#      ただし「ハッシュのキー」は絶対に訳さない。生成側はキーを
#      `formKey != "Normal Form"` のリテラル比較や is_custom_form の部分一致に
#      使っているため、訳すと静かに誤動作する。
#
#   2. 表示の直前に訳す (tr)
#      トレーナー名・フィールド名・ショップの品目名は、生のマークダウンの
#      `!battle(["Bart", :YOUNGSTER, 0])` のような指示行から英語文字列のまま
#      渡ってくる。これらは同時に検索キーでもあるので、表示の瞬間だけ訳す。
#
# 辞書に無い語は英語のまま返る。パッチが MissingNo 系のバグ名や内部マップ名を
# 意図的に英語で残しているため、これは異常ではない。
module JaNames
  DICT_PATH = File.expand_path('../_ja/dict.json', __dir__)
  UI_PATH = File.expand_path('../_ja/ui.yml', __dir__)
  SHOPS_PATH = File.expand_path('../_ja/shops.yml', __dir__)
  ENC_MAPS_PATH = File.expand_path('../_ja/enc-maps.yml', __dir__)

  class << self
    # WT_LANG=en を渡せば、辞書があっても英語版として生成できる。
    def enabled?
      return @enabled unless @enabled.nil?

      @enabled = ENV['WT_LANG'] != 'en' && File.exist?(DICT_PATH)
    end

    def dict
      @dict ||= enabled? ? JSON.parse(File.read(DICT_PATH)) : {}
    end

    # フィールド名は、生マークダウンの !battle(..., "Forest Field") で著者が
    # 手で書いているため、ゲーム本体の名前と綴りが揺れる。さらに
    # "Rainbow Field atop Forest Field" のような複合表記もある。
    #
    # 素直に辞書を引くだけだと 14 種 48 箇所が英語のまま残るので、
    # 表記ゆれの吸収と複合表記の分解をここで行う。
    FIELD_ALIASES = {
      'Cave Field' => 'Cave',
      'Mountain Field' => 'Mountain',
      'Wasteland Field' => 'Wasteland',
      'Underwater Field' => 'Underwater',
      'Murkwater Field' => 'Murkwater Surface',
      'Flower Garden' => 'Flower Garden Field',
      'Fairy Tale Arena' => 'Fairy Tale Field',
      'Crystal Cavern Field' => 'Crystal Cavern'
    }.freeze

    # "A atop B" は「B の上に A が乗っている」状態。表の 1 行に収めたいので、
    # 主となる A を先に出して B を括弧で添える。
    FIELD_COMPOUND = [
      [/\s+atop\s+/, :atop],
      [/\s+upon\s+/, :atop],
      [/\s+OR\s+/,   :alt]
    ].freeze

    # 表記ゆれの吸収規則は資料ページ側 (FieldNotes) でも使う。表を2箇所に
    # 持つと片方だけ直して食い違うので、ここから引かせる。
    def field_alias(name)
      FIELD_ALIASES[name]
    end

    def field(name)
      return name unless enabled? && name.is_a?(String)

      FIELD_COMPOUND.each do |pattern, kind|
        next unless name =~ pattern

        head, tail = name.split(pattern, 2)
        return kind == :atop ? "#{field(head)}（#{field(tail)}の上）" : "#{field(head)} または #{field(tail)}"
      end
      resolve_field(name)
    end

    def resolve_field(name)
      table = dict['fields'] || {}
      return table[name] if table.key?(name)

      aliased = FIELD_ALIASES[name]
      return table[aliased] || aliased if aliased

      # "Foo Field" <-> "Foo" の揺れを両方向で試す
      stripped = name.sub(/\s+(Field|Arena)\z/, '')
      return table[stripped] if table.key?(stripped)
      return table["#{name} Field"] if table.key?("#{name} Field")

      # ゲームに無い fork 独自の名前 (Random Field など) は対訳表で拾う
      ui(name)
    end

    def tr(category, value)
      return value unless enabled? && value.is_a?(String)

      table = dict[category.to_s] || {}
      return table[value] if table.key?(value)

      # 綴りの揺れを吸収する。攻略の原文は Poke Ball / PokeSnax / X-Attack と
      # 書くのに対し、ゲームデータ側は Poké Ball / PokéSnax / X Attack を使う。
      # 素直に引くと訳が当たらず英語のまま残るため、記号とアクセントを落として
      # もう一度引く。
      normalized_index(category.to_s)[normalize_key(value)] || value
    end

    def normalize_key(text)
      text.unicode_normalize(:nfkd).gsub(/\p{Mn}/, '').downcase.gsub(/[^a-z0-9]/, '')
    end

    def normalized_index(category)
      @normalized ||= {}
      @normalized[category] ||= (dict[category] || {}).each_with_object({}) do |(en, ja), acc|
        acc[normalize_key(en)] ||= ja
      end
    end

    # "Youngster Bart" のようにトレーナー種別と名前を続けて出す箇所用。
    # 日本語では種別と名前の間に空白を入れない方が収まりが良い。
    def trainer_label(type_title, trainer_name)
      name = tr('trainer_names', trainer_name)
      return "#{type_title} #{trainer_name}" unless enabled?

      "#{type_title} #{name}"
    end

    # 表の枠組み (見出し・ラベル・開閉ボタンなど) を訳す。これらはゲームデータ
    # ではなく生成側のコードに直接書かれているので、_ja/ui.yml で持つ。
    # キーは英語そのものなので、呼び出し側を読めば元の文言が分かる。
    def ui(text)
      return text unless enabled?

      ui_table[text] || text
    end

    def ui_table
      @ui_table ||= File.exist?(UI_PATH) ? YAML.safe_load(File.read(UI_PATH)) : {}
    end

    # ページの題名 (ブラウザのタブ名・目次見出し)。生成側のコードに直接
    # 書かれている文字列なので、辞書ではなく _ja/ui.yml で持つ。
    GAME_TITLES = { 'reborn' => 'ポケモンリボーン' }.freeze

    def game_title(long_name)
      return "Pokemon #{long_name.capitalize}" unless enabled?

      GAME_TITLES[long_name] || "Pokemon #{long_name.capitalize}"
    end

    # "Reborn Episode 1" のような章ページの題名。
    # 日本語版ではサイト名 (_config.yml の title) が既に作品名を含むので、
    # <title> が「ポケモンリボーン エピソード1 | ポケモンリボーン 日本語攻略」と
    # 重複しないよう、作品名は付けない。
    def page_title(long_name, slug, chapter_title)
      return "#{long_name.capitalize} #{chapter_title}" unless enabled?

      case slug
      when 'appendices' then '付録'
      when 'karma-files-paragon' then 'カルマファイル（パラゴン）'
      when 'karma-files-renegade' then 'カルマファイル（レネゲイド）'
      when /\Apostgame-episode-(\d+)\z/ then "クリア後 エピソード#{Regexp.last_match(1)}"
      when /\Aepisode-(\d+)\z/ then "エピソード#{Regexp.last_match(1)}"
      when /\Achapter-(\d+)\z/ then "第#{Regexp.last_match(1)}章"
      else chapter_title
      end
    end

    # 更新日時。英語の "21 Aug 2026 @ 20:13 GMT" は日本語ページでは読みにくい。
    def timestamp(time)
      return "#{time.strftime('%d %b %Y @ %H:%M')} GMT" unless enabled?

      "#{time.strftime('%Y年%-m月%-d日 %H:%M')} GMT"
    end

    # !enc(...) の第4引数で上書きされるマップ名。ショップ名と同じく著者の手書きで、
    # ゲームデータには無い。nil ならそのまま返して呼び出し側の既定に任せる。
    def enc_map(name)
      return name unless enabled? && name.is_a?(String)

      enc_map_table[name] || name
    end

    def enc_map_table
      @enc_map_table ||= File.exist?(ENC_MAPS_PATH) ? YAML.safe_load(File.read(ENC_MAPS_PATH)) : {}
    end

    # !shop(...) の品目名。道具とは限らず、ポケモン・わざマシン・コインも並ぶ。
    # 道具の辞書だけを引いていたため、これらが英語のまま残っていた。
    def shop_item(name)
      return name unless enabled? && name.is_a?(String)

      %w[items species].each do |cat|
        hit = tr(cat, name)
        return hit unless hit == name
      end

      # "TM45 Attract" のような合成名。番号と技名を別々に引く。
      m = name.match(/\A(TMX?\d+)\s+(.+)\z/)
      return "#{tr('items', m[1])} #{tr('moves', m[2])}" if m

      # "50 Coins" のような数量表記
      m = name.match(/\A(\d+)\s+Coins?\z/)
      return "#{m[1]}コイン" if m

      # "5x EV Tuners" のような個数つき表記。単数形に戻して引く。
      m = name.match(/\A(\d+)x?\s+(.+)\z/)
      if m
        singulars = [m[2], m[2].sub(/ies\z/, 'y'), m[2].sub(/s\z/, '')]
        singulars.each do |singular|
          base = tr('items', singular)
          return "#{base} #{m[1]}個" unless base == singular
        end
      end

      ui(name)
    end

    # 技教え人の料金。"3 Green Shards" のように数と色で書かれている。
    def shard_cost(text)
      return text unless enabled? && text.is_a?(String)

      m = text.match(/\A(\d+)\s+(Red|Blue|Green|Purple)\s+Shards?\z/)
      return "#{m[1]}個の#{ui("#{m[2]} Shard")}" if m

      m = text.match(/\A(\d+)\s+Coins?\z/)
      return "#{m[1]}コイン" if m

      ui(text)
    end

    # ショップ名・技教え人名。!shop("Department Store 3F (Left)", ...) のように
    # 指示行へ直接書かれた文字列なので、ゲームデータの辞書では引けない。
    def shop(title)
      return title unless enabled? && title.is_a?(String)

      shop_table[title] || title
    end

    def shop_table
      @shop_table ||= File.exist?(SHOPS_PATH) ? YAML.safe_load(File.read(SHOPS_PATH)) : {}
    end

    # --- ハッシュ書き換え -------------------------------------------------

    # {:SYM => {:name => "...", :desc => "..."}} 形式。
    def localize_flat!(hash, name_cat, desc_cat = nil, name_key = :name)
      return hash unless enabled?

      hash.each_value do |entry|
        next unless entry.is_a?(Hash)

        localize_entry!(entry, name_cat, desc_cat, name_key)
      end
      hash
    end

    # {:SYM => {"Normal Form" => {:name => "..."}}} 形式 (montext)。
    # 外側のキー (フォーム名) は触らない。
    def localize_nested!(hash, name_cat)
      return hash unless enabled?

      hash.each_value do |forms|
        next unless forms.is_a?(Hash)

        forms.each_value do |entry|
          localize_entry!(entry, name_cat, nil, :name) if entry.is_a?(Hash)
        end
      end
      hash
    end

    # {マップID => "Name"} 形式。ID で引くので同名マップを取り違えない。
    def localize_maps!(hash)
      return hash unless enabled?

      table = dict['map_names'] || {}
      hash.each_key do |id|
        ja = table[id.to_s]
        hash[id] = ja if ja
      end
      hash
    end

    # common.rb の FIELDS 定数 ({:SYM => "Forest Field"}) 用。
    def localize_fields(fields)
      return fields unless enabled?

      fields.transform_values { |name| field(name) }
    end

    private

    # 元の英語名を :name_en に退避しておく。ShopGetter の価格表が
    # 英語の道具名をキーにしているため、訳した後も英語を引ける必要がある。
    def localize_entry!(entry, name_cat, desc_cat, name_key)
      original = entry[name_key]
      if original.is_a?(String)
        entry[:name_en] = original
        entry[name_key] = tr(name_cat, original)
      end
      return unless desc_cat && entry[:desc].is_a?(String)

      entry[:desc] = tr(desc_cat, entry[:desc])
    end
  end
end
