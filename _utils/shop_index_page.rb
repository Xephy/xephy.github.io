# frozen_string_literal: true

require_relative 'ja_names'
require_relative 'shop_index'
require_relative 'doc_context'

# 「このどうぐはどこで買えるか」の一覧ページ。
#
# 表そのものは ShopIndex が本文の店の表から1行ずつ受け取っている。
# ここではそれをどうぐごとに並べ替えて出すだけ。
module ShopIndexPage
  module_function

  def esc(text)
    text.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;').gsub('"', '&quot;')
  end

  def chapter_label(title)
    m = title.to_s.match(/\A(.+?)[:：]/)
    m ? m[1].strip : title.to_s.strip
  end

  def shop_html(entry)
    ctx = entry[:context] || {}
    chapter = chapter_label(ctx[:chapter])
    link = ctx[:href] ? %(<a href="#{ctx[:href]}">#{esc(entry[:shop])}</a>) : esc(entry[:shop])
    meta = [chapter.empty? ? nil : esc(chapter), esc(entry[:price])].compact.join(' · ')
    %(<li data-ch="#{ctx[:seq] || 0}">#{link} <span class="sh-meta">#{meta}</span></li>)
  end

  def item_html(row)
    shops = row[:shops]
    many = shops.length > 1 ? %( <span class="sh-count">#{shops.length}店</span>) : ''
    first_ch = shops.map { |s| s.dig(:context, :seq) || 0 }.min

    <<~ROW
      <tr data-name="#{esc(row[:item])}" data-shops="#{shops.length}" data-ch="#{first_ch}">
        <td class="sh-item"><em>#{esc(row[:item])}</em>#{many}</td>
        <td class="sh-shops"><ul>#{shops.map { |s| shop_html(s) }.join}</ul></td>
      </tr>
    ROW
  end

  def filter_html(items)
    ja = JaNames.enabled?
    many = items.count { |r| r[:shops].length > 1 }

    seen = items.flat_map { |r| r[:shops].map { |s| s.dig(:context, :seq) } }.compact.uniq.sort
    options = seen.map { |i|
      %(<option value="#{i}">#{esc(chapter_label(DocContext.chapters[i]))}</option>)
    }.join

    <<~BAR
      <div class="ref-filter sh-filter" hidden>
        <div class="ref-filter-line">
          <input type="search" id="sh-q" class="ref-search" autocomplete="off"
                 placeholder="#{ja ? 'どうぐ名・店名で絞る' : 'Filter by item or shop'}">
          <span class="ref-count" role="status" aria-live="polite"></span>
        </div>
        <div class="ref-filter-line">
          <label class="ref-toggle" for="sh-upto">#{ja ? 'ここまで進んだ' : 'Progress'}</label>
          <select id="sh-upto" class="ref-select">
            <option value="">#{ja ? '全部見る' : 'All chapters'}</option>
            #{options}
          </select>
          <label class="ref-toggle"><input type="checkbox" id="sh-many">
            #{ja ? '2店以上で買える' : 'Sold in 2+ shops'}<span>#{many}</span></label>
          <button type="button" class="ref-reset">#{ja ? '条件を外す' : 'Clear'}</button>
        </div>
      </div>
    BAR
  end

  def build_page(game)
    items = ShopIndex.by_item
    return nil if items.empty?

    total_shops = items.sum { |r| r[:shops].length }
    shop_count = ShopIndex.entries.map { |e| [e[:shop], e.dig(:context, :href)] }.uniq.length
    title = JaNames.enabled? ? 'どうぐの買える店' : 'Shop Index'

    lead =
      if JaNames.enabled?
        ["攻略本文にある店の品揃えを、どうぐから引けるように並べ替えたものです。" \
         "#{items.length}品目 / #{total_shops}件 / #{shop_count}店。店名を押すと、その表が載っている本文へ飛べます。",
         "店は本文に出てくる順、つまり早く行ける順に並べています。" \
         "#{items.count { |r| r[:shops].length > 1 }}品目は2つ以上の店で扱っていて、値段が違うこともあります。"]
      else
        ["The walkthrough's shop tables, rearranged by item. " \
         "#{items.length} items / #{total_shops} listings / #{shop_count} shops.",
         "Shops are listed in walkthrough order, so the earliest one comes first."]
      end

    <<~PAGE
      ---
      title: #{title}
      permalink: /#{game}/shops/
      ---

      <p id="title-text">#{title}</p>

      <p class="ref-back"><a href="/#{game}/">#{JaNames.ui('Back to contents')}</a></p>

      #{lead[0]}

      #{lead[1]}

      #{filter_html(items)}

      <table class="sh-table">
      #{items.map { |r| item_html(r) }.join}
      </table>
    PAGE
  end
end
