require_relative 'common'
require_relative 'affinity'
require_relative 'function_wrapper'

# 見出し行末の Kramdown 属性 {#id}。bin/add-heading-ids が書き込む。
HEADING_ID = /\s*\{#([^}]+)\}\z/.freeze

def generate_md_text(game = 'reborn', scripts_dir)
  func_wrapper = FunctionWrapper.new(game, scripts_dir)

  def generate_md_pre_contents(game = 'reborn', version = nil)
    <<~PRE_CONTENTS
      ---
      title: #{JaNames.enabled? ? JaNames.ui('Single page') : "Pokemon #{LONGNAMES[game].capitalize} Walkthrough"}
      permalink: /#{LONGNAMES[game]}/all/
      ---

      <p id="title-text">#{JaNames.game_title(LONGNAMES[game])} #{JaNames.ui('Walkthrough')}</p>
      <h5> #{JaNames.ui('Walkthrough last updated')} #{JaNames.timestamp(Time.now)}</h5>
      <h5> #{JaNames.ui('Based on game ver.')} #{version}</h5>
      <p><a href="/#{LONGNAMES[game]}/">#{JaNames.ui('Read by episode')}</a></p>
    PRE_CONTENTS
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
      sections = chapter[:content].each_line.filter_map do |line|
        next unless line.start_with?('## ')

        title = line.strip[2..].strip
        %(<li><a href="#{base}##{anchor_for(title)}">#{escape_html(heading_text(title))}</a></li>)
      end

      <<~BLOCK
        <section class="book-toc-chapter">
          <h3><a href="#{base}">#{escape_html(heading_text(chapter[:title]))}</a></h3>
          <ul>
            #{sections.join("\n    ")}
          </ul>
        </section>
      BLOCK
    end

    %(<div class="book-toc">\n#{blocks.join("\n")}</div>\n)
  end

  def escape_html(text)
    text.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;')
  end

  def generate_toc_contents(game)
    toc = ''
    ['main', 'para', 'rene', 'post', 'appendices'].each do |chapter_type|
      chapter_num = 1
      loop do
        raw_md = load_chapter_md(game, chapter_type, chapter_num)
        break if !raw_md
        raw_md.each_line do |line|
          next unless line.start_with?('#')
          next if line[/^#+/].length >= 3 # Only does 2 levels for TOC
          indents = line[/^#+/].length - 1
          title = line.strip[indents + 1..].strip # Remove the leading '#' and any extra spaces
          anchor_link = anchor_for(title)
          toc += "#{'  ' * indents}- [#{heading_text(title)}](##{anchor_link})\n"
        end
        chapter_num += 1
        break if chapter_type == "appendices"
      end
    end
    toc + "\n"
  end

  def generate_md_post_contents
    ''
  end

  def generate_chapter_contents(game, scripts_dir, type, num, func_wrapper)
    raw_md = load_chapter_md(game, type, num)
    return nil if !raw_md

    # Store chapter text as an array of lines - join them at the end
    res = []
    raw_md.each_line do |line|
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
    Affinity.apply(res.join)
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
  game_version = detect_game_version(game, scripts_dir)
  res += generate_md_pre_contents(game, game_version)
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
  
  # Return both monolithic and chapters
  index = <<~INDEX
    ---
    title: #{JaNames.enabled? ? JaNames.ui('Contents') : "Pokemon #{LONGNAMES[game].capitalize} Walkthrough"}
    permalink: /#{LONGNAMES[game]}/
    ---

    <p id="title-text">#{JaNames.game_title(LONGNAMES[game])} #{JaNames.ui('Walkthrough')}</p>
    <h5> #{JaNames.ui('Walkthrough last updated')} #{JaNames.timestamp(Time.now)}</h5>
    <h5> #{JaNames.ui('Based on game ver.')} #{game_version}</h5>
    <p><a href="/#{LONGNAMES[game]}/all/">#{JaNames.ui('Single page')}</a></p>

    #{generate_index_contents(game, chapters)}
  INDEX

  {
    monolithic: res.strip,
    chapters: chapters,
    index: index
  }
end
