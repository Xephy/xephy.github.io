# The Markdown to be processed by Jekyll is not committed directly - instead, it is processed
# by this script to ensure game data is being pulled effectively.
# Run with arguments <game>, <scripts directory>, <outputfile path>, to generate markdown appropriately.

require 'fileutils'
require_relative '_utils/md_generator'
require_relative '_utils/chapter_nav'

# Check for correct number of arguments
if ARGV.length != 3
  puts "Usage: ruby wt_generator.rb <game> <scripts directory> <output file>"
  exit 1
end

# Assign arguments to variables
game = ARGV[0]
scripts_dir = ARGV[1]
output_file = ARGV[2]

# Validate game type
unless ['reborn', 'rejuv', 'deso'].include?(game)
  puts "Invalid game type. Please specify 'reborn', 'deso', or 'rejuv'."
  exit 1
end

# Generate markdown content based on the game type
result = generate_md_text(game, scripts_dir)
markdown_contents = result[:monolithic]
chapters = result[:chapters]
puts "Generated markdown contents for #{game}!"
puts "Generated #{chapters.length} paginated chapters"

# Write monolithic content to the specified file
begin
  if File.exist?(output_file)
    timestamp = Time.now.utc.strftime("%Y%m%dT%H%M%SZ")
    dir = File.dirname(output_file)
    base = File.basename(output_file, "")
    new_name = File.join(dir, "_arch", "#{base}.#{timestamp}")
    File.rename(output_file, new_name)
    puts "Existing file renamed to #{new_name}"
  end

  File.open(output_file, 'w') do |f|
    f.write(markdown_contents)
  end

  puts "Wrote contents to #{output_file}!"
rescue => e
  STDERR.puts "Error writing output file: #{e.message}"
  exit 1
end

# Write paginated chapter files
begin
  chapters_dir = File.dirname(output_file)
  paginated_dir = File.join(chapters_dir, "#{game}-chapters")
  FileUtils.mkdir_p(paginated_dir)

  chapters.each_with_index do |chapter, chapter_index|
    page_title = JaNames.page_title(LONGNAMES[game], chapter[:slug], chapter[:title])

    # 前後移動と全章一覧。上下に同じものを置いて、読み終わった位置からも
    # 次へ進めるようにする。
    nav = ChapterNav.build(chapters, chapter_index, LONGNAMES[game])

    # 章内の節目次。CSS グリッドで本文の横に固定表示するため、本文と同じ
    # 階層 (#main_content の直下) に置く必要がある。ラップする div を挟むと
    # kramdown が中のマークダウンを処理しなくなるので、兄弟のまま並べる。
    toc = PageToc.build(chapter[:content])

    page_content = <<~PAGE_CONTENTS
      ---
      title: "#{page_title}"
      permalink: /#{LONGNAMES[game]}/#{chapter[:slug]}/
      ---

      #{nav}

      #{toc}

      #{chapter[:content]}

      #{nav}
    PAGE_CONTENTS

    page_file = File.join(paginated_dir, "#{chapter[:slug]}.md")
    File.write(page_file, page_content.strip)
  end

  # 目次ページ。permalink が /<game>/ なので、トップからの着地点はこれになる。
  File.write(File.join(paginated_dir, 'contents.md'), result[:index].strip)

  # 章の読み順には入らない資料ページ (好感度まとめなど)。
  (result[:pages] || {}).each do |name, contents|
    File.write(File.join(paginated_dir, "#{name}.md"), contents.strip)
    puts "Generated reference page #{name}.md"
  end

  # ポケモン個別ページ。数が多い (805種) ので専用のディレクトリに置き、
  # kramdown を通さずに済むよう .html で書き出す。
  mon_pages = result[:mon_pages] || {}
  unless mon_pages.empty?
    mon_dir = File.join(chapters_dir, "#{game}-mon")
    FileUtils.mkdir_p(mon_dir)
    written = 0
    mon_pages.each do |slug, contents|
      path = File.join(mon_dir, "#{slug}.html")
      body = "#{contents.strip}\n"
      # 中身が変わらないファイルは触らない。毎回 805 個を書き換えると、
      # 生成物をコミットしているこのリポジトリが際限なく膨らむ。
      next if File.exist?(path) && File.read(path) == body

      File.write(path, body)
      written += 1
    end
    puts "Generated #{mon_pages.length} Pokemon pages in #{mon_dir} (#{written} changed)"
  end

  puts "Generated #{chapters.length} paginated chapter files in #{paginated_dir}"
  puts "Generated contents page at /#{LONGNAMES[game]}/"
rescue => e
  STDERR.puts "Error writing paginated chapter files: #{e.message}"
  exit 1
end
