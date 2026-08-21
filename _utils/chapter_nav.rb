# frozen_string_literal: true

require_relative 'ja_names'

# 章ページ (episode-1 など) の上下に置くナビゲーションを組み立てる。
#
# 一枚版 (/reborn/) は 3.6MB あって開くのが重い。章ページは 1本 120KB 程度で、
# 生成自体は元から行われていたが、どこからもリンクされておらず到達できなかった。
# ここで前後移動と全章一覧を挿し込んで、分割版だけで読み通せるようにする。
#
# ラベルを Liquid ではなく Ruby 側で解決しているのは、対訳表 (_ja/ui.yml) が
# リポジトリ直下にあり、Jekyll の source (src/) の外なので Liquid から見えない
# ため。訳の管理を1箇所に保つ狙いもある。
module ChapterNav
  module_function

  def path(game, slug)
    "/#{game}/#{slug}/"
  end

  # 見出しから "Episode 1: Reborn, the City of Ruin" のような表題を作る。
  def label(chapter)
    chapter[:title].to_s.strip
  end

  def build(chapters, index, game)
    prev_ch = index.positive? ? chapters[index - 1] : nil
    next_ch = index < chapters.length - 1 ? chapters[index + 1] : nil

    links = chapters.each_with_index.map do |ch, i|
      current = i == index
      href = path(game, ch[:slug])
      if current
        %(<li class="chapter-nav-current"><strong>#{escape(label(ch))}</strong></li>)
      else
        %(<li><a href="#{href}">#{escape(label(ch))}</a></li>)
      end
    end.join("\n      ")

    prev_html =
      if prev_ch
        %(<a class="chapter-nav-prev" href="#{path(game, prev_ch[:slug])}">) +
          %(&larr; #{ui('Previous')}: #{escape(label(prev_ch))}</a>)
      else
        '<span class="chapter-nav-prev"></span>'
      end

    next_html =
      if next_ch
        %(<a class="chapter-nav-next" href="#{path(game, next_ch[:slug])}">) +
          %(#{ui('Next')}: #{escape(label(next_ch))} &rarr;</a>)
      else
        '<span class="chapter-nav-next"></span>'
      end

    <<~NAV
      <nav class="chapter-nav">
        #{prev_html}
        #{next_html}
        <details class="chapter-nav-toc">
          <summary>#{ui('Contents')}</summary>
          <ol>
            #{links}
          </ol>
          <p><a href="/#{game}/">#{ui('Single page')}</a></p>
        </details>
      </nav>
    NAV
  end

  def ui(text)
    JaNames.ui(text)
  end

  def escape(text)
    text.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;')
  end
end

# 章の中の節目次。1章が最大 8,700 行あるので、章ナビ (前後移動と全章一覧)
# だけでは章の内部を移動できない。
#
# 見出しは "## ネオオパール区 {#neo-opal-ward}" の形で残っているので、
# ここから拾う。ID を kramdown に自動採番させると数字始まりの見出しが
# 壊れるため、生成側で明示 ID を振ってある。それをそのまま使う。
module PageToc
  module_function

  HEADING = /^(\#{2,3})[ \t]+(.+?)[ \t]*\{\#([^}]+)\}[ \t]*$/.freeze

  def build(content)
    items = content.to_s.scan(HEADING).map do |hashes, text, id|
      { level: hashes.length, text: text.strip, id: id }
    end
    return '' if items.length < 2

    lis = items.map do |it|
      %(<li class="page-toc-l#{it[:level]}"><a href="##{it[:id]}">#{escape(it[:text])}</a></li>)
    end.join("\n    ")

    # details にしておくと JavaScript が無くても畳める。既定は開いた状態で、
    # 狭い画面だけ読み込み時に閉じる (myscripts.js)。
    <<~TOC
      <details class="page-toc" open>
        <summary>#{JaNames.ui('In this chapter')}</summary>
        <ul>
          #{lis}
        </ul>
      </details>
    TOC
  end

  def escape(text)
    text.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;')
  end
end
