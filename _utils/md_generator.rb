require_relative 'common'
require_relative 'chapter_nav'
require_relative 'affinity'
require_relative 'password_filter'
require_relative 'affinity_index'
require_relative 'field_notes'
require_relative 'doc_context'
require_relative 'field_usage'
require_relative 'badge_index'
require_relative 'encounter_index'
require_relative 'encounter_index_page'
require_relative 'shop_index'
require_relative 'tutor_index'
require_relative 'shop_index_page'
require_relative 'machine_index_page'
require_relative 'evolution_index_page'
require_relative 'pulsedex_page'
require_relative 'reference_pages'
require_relative 'changelog'
require_relative 'trainer_index'
require_relative 'mon_page'
require_relative 'move_page'
require_relative 'spoiler'
require_relative 'function_wrapper'

# 見出し行末の Kramdown 属性 {#id}。bin/add-heading-ids が書き込む。
HEADING_ID = /\s*\{#([^}]+)\}\z/.freeze

# 目次を索引として引くために、節ごとに拾う固有名詞。見出しの文字だけでは
# 「シグムンド」のような人名で引けない。
TOC_KEY_PATTERNS = [/<strong>VS: ([^<]+)<\/strong>/, /<strong>ショップ: ([^<]+)<\/strong>/].freeze

def generate_md_text(game = 'reborn', scripts_dir)
  func_wrapper = FunctionWrapper.new(game, scripts_dir)

  def generate_md_pre_contents(game = 'reborn', version = nil)
    <<~PRE_CONTENTS
      ---
      title: #{JaNames.enabled? ? JaNames.ui('Single page') : "Pokemon #{LONGNAMES[game].capitalize} Walkthrough"}
      permalink: /#{LONGNAMES[game]}/all/
      # 章ページと同じ本文をもう一度持つページ。検索では章ページを出したいので
      # ここは索引から外し、sitemap にも載せない。読む人向けのリンクは残す。
      noindex: true
      sitemap: false
      ---

      <p id="title-text">#{JaNames.game_title(LONGNAMES[game])} #{JaNames.ui('Walkthrough')}</p>
      <h5> #{JaNames.ui('Walkthrough last updated')} #{JaNames.timestamp(Time.now)}</h5>
      <h5> #{JaNames.ui('Based on game ver.')} #{version}</h5>
      <p><a href="/#{LONGNAMES[game]}/">#{JaNames.ui('Read by episode')}</a>#{reference_links(game)}</p>
    PRE_CONTENTS
  end

  # 見出しの並びに続けて置く資料ページへのリンク。
  def reference_links(game)
    ReferencePages.all.map { |p|
      %( / <a href="#{ReferencePages.path(LONGNAMES[game], p)}">#{ReferencePages.label(p)}</a>)
    }.join
  end

  # 見出し行から表示文と id を取り出す。
  #
  # 生マークダウンの見出しには {#id} が書かれている (bin/add-heading-ids)。
  # 見出しを日本語に訳すと英字が消えて機械生成のアンカーが空に潰れるため、
  # 識別子は文言から独立させてある。{#id} が無い見出しは従来どおり英語から作る。
  def heading_text(title)
    title.sub(HEADING_ID, '').strip
  end

  def anchor_for(title)
    m = title.match(HEADING_ID)
    return m[1] if m

    # {#id} が無い見出し (rejuv / deso 側) 用。Kramdown の auto_ids と同じ手順で
    # 作る。従来の式は先頭の数字を残していたため、"1 Badge Quests" のような
    # 見出しで目次のリンク先と実際の id が食い違っていた。
    heading_text(title)
      .sub(/\A[^a-zA-Z]+/, '')
      .gsub(/[^a-zA-Z0-9 -]/, '')
      .tr(' ', '-')
      .downcase
  end

  # 章ページへ飛ぶ目次。トップから来た人が最初に着く /<game>/ はこれにする。
  # 一枚版は 3.6MB あり、最初の着地としては重すぎるため。
  # 目次ページの本体。29章 × 各10節ほどあるので、章ごとに区切りを付けて
  # CSS 側で段組にできるよう、素のリストではなく章単位の HTML で出す。
  def generate_index_contents(game, chapters)
    blocks = chapters.map do |chapter|
      base = "/#{LONGNAMES[game]}/#{chapter[:slug]}/"
      sections = section_items(chapter[:content], base)

      <<~BLOCK
        <section class="book-toc-chapter">
          <h3><a href="#{base}">#{escape_html(heading_text(chapter[:title]))}</a></h3>
          <ul>
            #{sections.join("\n    ")}
          </ul>
        </section>
      BLOCK
    end

    ref = ReferencePages.all.map { |p|
      %(<li><a href="#{ReferencePages.path(LONGNAMES[game], p)}">) +
        %(#{ReferencePages.label(p)}</a></li>)
    }
    unless ref.empty?
      blocks << <<~BLOCK
        <section class="book-toc-chapter book-toc-ref">
          <h3>#{JaNames.ui('Reference')}</h3>
          <ul>
            #{ref.join("\n    ")}
          </ul>
        </section>
      BLOCK
    end

    %(#{toc_filter(chapters, blocks)}<div class="book-toc">\n#{blocks.join("\n")}</div>\n)
  end

  # 目次の1章分の項目。小節 (###) も入れる。目次を絞り込みの索引として
  # 使うので、拾える見出しは多いほうがよい (節207 + 小節67)。
  #
  # 見出しの文字だけでは「シグムンド」のような人名で引けない。節ごとに
  # トレーナー名とショップ名を集めて data-keys に持たせる (のべ1,015語)。
  # 表示はしないので、目次の見た目は変わらない。
  def section_items(content, base)
    items = []
    keys = nil

    content.each_line do |line|
      level = line.start_with?('### ') ? 3 : (line.start_with?('## ') ? 2 : nil)
      if level
        title = line.strip[level..].strip
        keys = []
        items << { level: level, title: title, keys: keys }
        next
      end
      next unless keys

      TOC_KEY_PATTERNS.each { |re| line.scan(re) { |m| keys << m[0].strip } }
    end

    items.map do |it|
      cls = it[:level] == 3 ? ' class="book-toc-sub"' : ''
      data = it[:keys].uniq
      attr = data.empty? ? '' : %( data-keys="#{escape_html(data.join(' '))}")
      %(<li#{cls}#{attr}><a href="#{base}##{anchor_for(it[:title])}">) +
        %(#{escape_html(heading_text(it[:title]))}</a></li>)
    end
  end

  # 目次を索引として引けるようにする操作子。
  #
  # 攻略本文29章には検索が無く、何かを探すには 11.7MB の一枚版を開いて
  # ブラウザの検索を使うしかなかった。目次にはすでに全章・全節の見出しと
  # リンクが並んでいるので、ここを絞り込めるようにするのが一番安い。
  def toc_filter(chapters, blocks)
    sections = blocks.sum { |b| b.scan('<li').length }
    ja = JaNames.enabled?

    <<~BAR
      <div class="ref-filter toc-filter" hidden>
        <div class="ref-filter-line">
          <input type="search" id="toc-q" class="ref-search" autocomplete="off"
                 placeholder="#{ja ? '章・節の名前で絞る（地名・人物名・店名でも引ける）' : 'Filter chapters and sections'}">
          <span class="ref-count" role="status" aria-live="polite"></span>
          <button type="button" class="ref-reset">#{ja ? '条件を外す' : 'Clear'}</button>
        </div>
      </div>
    BAR
  end

  def escape_html(text)
    text.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;')
  end

  # 一枚版の冒頭に置く目次。
  #
  # 以前は章29本と節207本を平らな箇条書きで並べていたため、本文が始まる
  # までに何画面も送る必要があった。章ごとに畳んで、開いた章だけ節が
  # 見えるようにする。生のマークダウンではなく HTML で書き出すのは、
  # details の中に入れると kramdown が中身の処理を止めてしまうため。
  def generate_toc_contents(game)
    chapters = []
    ['main', 'para', 'rene', 'post', 'appendices'].each do |chapter_type|
      chapter_num = 1
      loop do
        raw_md = load_chapter_md(game, chapter_type, chapter_num)
        break if !raw_md
        raw_md.each_line do |line|
          next unless line.start_with?('#')
          level = line[/^#+/].length
          next if level >= 3 # Only does 2 levels for TOC
          title = line.strip[level..].strip
          entry = { text: heading_text(title), anchor: anchor_for(title) }
          if level == 1
            chapters << entry.merge(sections: [])
          elsif chapters.any?
            chapters.last[:sections] << entry
          end
        end
        chapter_num += 1
        break if chapter_type == "appendices"
      end
    end

    return "\n" if chapters.empty?

    blocks = chapters.map do |ch|
      lis = ch[:sections].map do |sec|
        %(<li><a href="##{sec[:anchor]}">#{escape_html(sec[:text])}</a></li>)
      end.join("\n      ")
      sections = ch[:sections].empty? ? '' : "\n    <ul>\n      #{lis}\n    </ul>"
      <<~CHAPTER
        <details class="book-toc-chapter">
          <summary><a href="##{ch[:anchor]}">#{escape_html(ch[:text])}</a></summary>#{sections}
        </details>
      CHAPTER
    end

    <<~TOC
      <nav class="book-toc book-toc-inline">
      #{blocks.join}
      </nav>

    TOC
  end

  def generate_md_post_contents
    ''
  end

  def generate_chapter_contents(game, scripts_dir, type, num, func_wrapper)
    raw_md = load_chapter_md(game, type, num)
    return nil if !raw_md

    # Store chapter text as an array of lines - join them at the end
    res = []
    # 出現表の逆引きページは「どの節に載っていた表か」を必要とする。指示行を
    # 展開する側でしか見出しが分からないので、ここで見出しを追いかけて渡す。
    chapter_title = nil
    chapter_slug = nil
    chapter_seq = nil
    DocContext.clear_position!

    raw_md.each_line do |line|
      if line.start_with?('#') && (m = line.chomp.match(/\A(\#{1,3})[ \t]+(.+?)[ \t]*\{\#([^}]+)\}[ \t]*\z/))
        level, heading, id = m[1].length, m[2].strip, m[3]
        if level == 1
          chapter_title = heading
          chapter_slug = generate_intelligent_slug(line.strip[2..].strip, type, num)
          chapter_seq = DocContext.begin_chapter(chapter_title, chapter_slug)
          DocContext.current = { chapter: chapter_title, seq: chapter_seq, section: chapter_title,
                                 href: "/#{LONGNAMES[game]}/#{chapter_slug}/" }
        elsif chapter_slug
          DocContext.current = { chapter: chapter_title, seq: chapter_seq, section: heading,
                                 href: "/#{LONGNAMES[game]}/#{chapter_slug}/##{id}" }
          BadgeIndex.scan_heading(heading)
        end
      elsif chapter_slug
        BadgeIndex.scan_line(line)
      end

      if line.strip.empty? || line[0] != '!'
        res << line
      elsif line[0] == '!'
        # Function Wrapper class does the magic of taking a line
        # beginning with ! and transforming it into a dynamic output:
        # taking a shortened function name, arguments, and globals
        function_result = func_wrapper.evaluate_function_from_string(line)
        res << function_result
      end
    end
    Spoiler.apply(Affinity.apply(PasswordFilter.apply(res.join, LONGNAMES[game]), LONGNAMES[game]))
  end

  def generate_intelligent_slug(title, chapter_type, chapter_num)
    # 見出しに {#id} があればそれが URL。訳しても URL が動かないようにするため、
    # 以下の英語前提の判定より先に効かせる。
    m = title.match(HEADING_ID)
    return m[1] if m

    # Special handling for .Karma Files sections
    if title.start_with?('.Karma Files')
      if title.include?('Paragon')
        return 'karma-files-paragon'
      elsif title.include?('Renegade')
        return 'karma-files-renegade'
      end
    end

    # Appendices
    if chapter_type == 'appendices'
      return 'appendices'
    end

    # Postgame episodes (post chapter_type)
    if chapter_type == 'post'
      return "postgame-episode-#{chapter_num}"
    end

    # Extract episode/chapter number from title
    if title =~ /^Episode\s+(\d+)/i
      return "episode-#{$1}"
    elsif title =~ /^Chapter\s+(\d+)/i
      return "chapter-#{$1}"
    elsif title =~ /^Postgame\s+Episode\s+(\d+)/i
      return "postgame-episode-#{$1}"
    else
      # Fallback: use chapter-type-num format
      return "#{chapter_type}-#{chapter_num}"
    end
  end

  def extract_first_level_header(content)
    content.each_line do |line|
      return line.strip[2..].strip if line.start_with?('# ')
    end
    nil
  end

  res = ''
  EncounterIndex.reset!
  ShopIndex.reset!
  TutorIndex.reset!
  MoveIndex.reset!
  TrainerIndex.reset!
  FieldUsage.reset!
  BadgeIndex.reset!
  DocContext.reset!
  game_version = detect_game_version(game, scripts_dir)
  res += generate_md_pre_contents(game, game_version)
  # 読んでいる最中も章を移動できるよう、章ページと同じ固定サイドバーを置く。
  # 左に浮かせる要素なので、回り込ませたい中身より前に置く必要がある。
  sidebar_anchor = res.length
  res += generate_toc_contents(game)
  
  chapters = []
  ['main', 'para', 'rene', 'post', 'appendices'].each do |chapter_type|
    chapter_num = 1
    loop do
      curr = generate_chapter_contents(game, scripts_dir, chapter_type, chapter_num, func_wrapper)
      break if !curr
      
      first_header = extract_first_level_header(curr)
      if first_header
        slug = generate_intelligent_slug(first_header, chapter_type, chapter_num)
        chapters << { title: heading_text(first_header), slug: slug, content: curr }
      end
      
      res += "#{curr}\n"
      chapter_num += 1
      break if chapter_type == "appendices"
    end
  end
  res += generate_md_post_contents

  # 章の一覧を固定サイドバーとして差し込む。h1 が出そろってからでないと
  # 作れないので、本文を組み終えたこの位置で入れる。挿入先は目次の直後。
  sidebar = PageToc.build_top(res)
  res = res[0...sidebar_anchor] + sidebar + res[sidebar_anchor..] unless sidebar.empty?
  
  # Return both monolithic and chapters
  index = <<~INDEX
    ---
    title: #{JaNames.enabled? ? JaNames.ui('Contents') : "Pokemon #{LONGNAMES[game].capitalize} Walkthrough"}
    permalink: /#{LONGNAMES[game]}/
    description: #{JaNames.enabled? ? '"ポケモンリボーンの攻略目次。本編エピソード1〜19とクリア後全9話、付録（ものひろい表・採掘確率・パスワード一覧）を日本語でまとめています。"' : '"Walkthrough contents."'}
    ---

    <p id="title-text">#{JaNames.game_title(LONGNAMES[game])} #{JaNames.ui('Walkthrough')}</p>
    <h5> #{JaNames.ui('Walkthrough last updated')} #{JaNames.timestamp(Time.now)}</h5>
    <h5> #{JaNames.ui('Based on game ver.')} #{game_version}</h5>
    <p><a href="/#{LONGNAMES[game]}/all/">#{JaNames.ui('Single page')}</a>#{JaNames.enabled? ? %( / <a href="/patch/">日本語化パッチの導入方法</a>) : ''}</p>

    #{Changelog.recent_html(LONGNAMES[game])}

    #{generate_index_contents(game, chapters)}
  INDEX

  # 章とは別に置く資料ページ。読み順に混ぜたくないので chapters には入れず、
  # permalink だけ /<game>/... に並べる。
  pages = {}
  encounter_page = EncounterIndexPage.build_page(LONGNAMES[game], scripts_dir)
  pages['pokemon'] = encounter_page if encounter_page
  shop_page = ShopIndexPage.build_page(LONGNAMES[game])
  pages['shops'] = shop_page if shop_page
  tm_page = MachineIndexPage.build_page(LONGNAMES[game], func_wrapper.item_hash,
                                        func_wrapper.move_hash, chapters)
  pages['tms'] = tm_page if tm_page
  evo_page = EvolutionIndexPage.build_page(LONGNAMES[game], func_wrapper.item_hash,
                                           func_wrapper.move_hash, func_wrapper.pokemon_hash,
                                           func_wrapper.map_hash)
  pages['evolutions'] = evo_page if evo_page
  pulse_page = PulsedexPage.build_page(LONGNAMES[game], scripts_dir, func_wrapper.pokemon_hash)
  pages['pulsedex'] = pulse_page if pulse_page
  field_page = FieldNotes.build_page(LONGNAMES[game], scripts_dir)
  pages['fields'] = field_page if field_page
  affinity_page = AffinityIndex.build_page(chapters, LONGNAMES[game])
  pages['affinity'] = affinity_page if affinity_page
  # 更新履歴。ゲームの資料ではないので ReferencePages (資料の並び) には入れない。
  # 入口は目次ページの「更新情報」から。
  changelog_page = Changelog.build_page(LONGNAMES[game])
  pages['changelog'] = changelog_page if changelog_page

  # ポケモン1種につき1ページ。章の索引 (出現・教え人・マシン・トレーナー) が
  # 出そろってからでないと組めないので、資料ページの後に置く。
  mon_pages = MonPage.build_pages(LONGNAMES[game], scripts_dir, chapters,
                                  pokemon: func_wrapper.pokemon_hash,
                                  item: func_wrapper.item_hash,
                                  move: func_wrapper.move_hash,
                                  type: func_wrapper.type_hash,
                                  ability: func_wrapper.ability_hash,
                                  map: func_wrapper.map_hash,
                                  field: load_field_hash(game, scripts_dir))

  # わざ1本につき1ページ。逆引きの中身は個別ページを組む過程で MoveIndex に
  # 溜まるので、必ず MonPage の後に置く。
  move_pages = MovePage.build_pages(LONGNAMES[game], scripts_dir,
                                    { pokemon: func_wrapper.pokemon_hash,
                                      move: func_wrapper.move_hash },
                                    MonPage.last_context)

  {
    monolithic: res.strip,
    chapters: chapters,
    index: index,
    pages: pages,
    mon_pages: mon_pages,
    move_pages: move_pages
  }
end
