# frozen_string_literal: true

require 'json'
require_relative 'ja_names'

# PULSE図鑑。
#
# ゲーム内ではポケギアのアプリで読めるが、説明文は512x384の画像に焼き込まれて
# いて、通常のメッセージ表には出てこない。日本語化パッチが画像を描き直して
# いるので訳文は存在するが、画像なので検索も引用もできなかった。
#
# 14体。PULSEDATA (番号・種族・フォーム) はゲームのスクリプトから、訳文と
# タイプ・とくせいは _ja/pulsedex.json (パッチが書き出す) から取る。
#
# 能力値は画像の棒グラフでしか示されておらず数値が無いので、載せない。
module PulsedexPage
  module_function

  DATA_PATH = File.expand_path('../_ja/pulsedex.json', __dir__)
  ENTRY = /^  :(\w+) =>\s*\{(.*?)^  \},/m.freeze

  def dict
    @dict ||= File.exist?(DATA_PATH) ? (JSON.parse(File.read(DATA_PATH))['entries'] || {}) : {}
  end

  def esc(text)
    text.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;').gsub('"', '&quot;')
  end

  # PulseDex.rb の PULSEDATA を読む。eval するとゲーム側の定数が要るので、
  # 必要な3項目だけ取り出す。
  def entries(scripts_dir)
    path = File.join(scripts_dir, 'PulseDex.rb')
    return [] unless File.exist?(path)

    body = File.read(path)[/^PULSEDATA = \{.*?^\}/m].to_s
    body.scan(ENTRY).map do |key, block|
      { key: key,
        label: block[/:name\s*=>\s*"([^"]*)"/, 1].to_s,
        species: block[/:species\s*=>\s*:(\w+)/, 1],
        form: block[/:form\s*=>\s*"([^"]*)"/, 1] }
    end
  end

  def type_badge(sym)
    label = JaNames.tr('types', sym.to_s.capitalize)
    %(<span class="type-badge type-#{sym.to_s.downcase}">#{esc(label)}</span>)
  end

  def card(entry, pokemon_hash)
    info = dict[entry[:key]] || {}
    number = entry[:label][/\A([0-9A-Z]+)\./, 1]
    species_sym = entry[:species].to_s.to_sym
    forms = pokemon_hash[species_sym]
    base = forms && forms.keys.find { |k| k.is_a?(String) }
    name = base ? forms[base][:name] : entry[:species].to_s

    types = Array(info['types']).map { |t| type_badge(t) }.join
    ability = info['ability_en'] ? JaNames.tr('abilities', info['ability_en']) : nil
    # Arc_Pulse だけ説明文が短い文の並び (13行の詠唱) になっている。
    desc = info['desc']
    desc = desc.is_a?(Array) ? desc.map { |l| esc(l) }.join('<br>') : esc(desc.to_s)

    <<~CARD
      <section class="pulse-card">
        <h3 class="pulse-head"><span class="pulse-no">PULSE #{esc(number)}</span>#{esc(name)}</h3>
        <p class="pulse-meta">#{types}#{ability ? %(<span class="pulse-ability">#{JaNames.ui('Ability:')} #{esc(ability)}</span>) : ''}</p>
        <p class="pulse-desc">#{desc}</p>
      </section>
    CARD
  end

  def build_page(game, scripts_dir, pokemon_hash)
    rows = entries(scripts_dir)
    return nil if rows.empty? || dict.empty?

    title = JaNames.enabled? ? 'PULSE図鑑' : 'Pulse Dex'
    lead =
      if JaNames.enabled?
        ["ゲーム内のポケギアで読める「PULSE図鑑」の写しです。#{rows.length}体。",
         "本編では説明文が画像に焼き込まれていて、検索も引用もできません。" \
         "ここでは組み直してあるので、種族名や語句で探せます。" \
         "能力値は画像の棒グラフでしか示されておらず数値が無いので、載せていません。",
         "**ネタバレ注意** — 物語の核心に触れる文章が含まれます。"]
      else
        ["A transcript of the in-game Pulse Dex. #{rows.length} entries.",
         "The descriptions are baked into images in game, so they cannot be searched or quoted there.",
         "**Spoilers** - these entries give away central parts of the story."]
      end

    <<~PAGE
      ---
      title: #{title}
      permalink: /#{game}/pulsedex/
      ---

      <p id="title-text">#{title}</p>

      <p class="ref-back"><a href="/#{game}/">#{JaNames.ui('Back to contents')}</a></p>

      #{lead[0]}

      #{lead[1]}

      #{lead[2]}
      {: .affinity-warning}

      <div class="pulse-list">
      #{rows.map { |r| card(r, pokemon_hash) }.join}
      </div>
    PAGE
  end
end
