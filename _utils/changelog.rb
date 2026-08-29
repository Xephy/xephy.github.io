# frozen_string_literal: true

require 'yaml'
require_relative 'ja_names'

# 更新履歴。中身は _ja/changelog.yml に手で書く。
#
# 一般公開した以上、戻ってきた人が「前と何が変わったのか」を知る場所が要る。
# 目次の「最終更新」はビルドした時刻なので、作り直すたびに動く。中身が
# 変わっていない日でも新しい日付になり、何が変わったかは答えられない。
#
# 目次ページには新しいほうから数件だけ出し、全部は /<game>/changelog/ に置く。
# 目次に全部並べると、肝心の章の一覧が下へ押し出される。
#
# コミットの履歴からは作らない。753件のうち読む側から見えるものは一部で、
# 「ads.txt を置く」のような表題は読者には意味がないため。
module Changelog
  module_function

  PATH = File.expand_path('../_ja/changelog.yml', __dir__)

  # 目次ページに出す件数。日付ではなく項目で数える。1日に8件足した日が
  # あるので、日付で切ると目次が長くなりすぎる。
  RECENT = 5

  KIND_JA = { 'new' => '新機能', 'add' => '追加', 'fix' => '修正', 'imp' => '改善' }.freeze
  KIND_EN = { 'new' => 'New', 'add' => 'Added', 'fix' => 'Fixed', 'imp' => 'Improved' }.freeze

  def esc(text)
    text.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;').gsub('"', '&quot;')
  end

  def entries
    @entries ||= File.exist?(PATH) ? (YAML.safe_load(File.read(PATH)) || []) : []
  end

  def reset!
    @entries = nil
  end

  # 日付をまたいで平らに並べたもの。目次ページはここから頭を取る。
  def flat
    entries.flat_map { |day|
      (day['items'] || []).map { |item| item.merge('date' => day['date']) }
    }
  end

  def kind_label(kind)
    (JaNames.enabled? ? KIND_JA[kind] : KIND_EN[kind]) || ''
  end

  # 「8/29」。年は見出しの側にあるので繰り返さない。
  def short_date(iso)
    y, m, d = iso.to_s.split('-')
    return esc(iso) unless y && m && d

    JaNames.enabled? ? "#{m.to_i}/#{d.to_i}" : "#{m}/#{d}"
  end

  def long_date(iso)
    y, m, d = iso.to_s.split('-')
    return esc(iso) unless y && m && d

    JaNames.enabled? ? "#{y}年#{m.to_i}月#{d.to_i}日" : "#{y}-#{m}-#{d}"
  end

  def kind_chip(kind)
    label = kind_label(kind)
    return '' if label.empty?

    %(<span class="news-kind is-#{esc(kind)}">#{esc(label)}</span>)
  end

  # 1項目。href があれば行き先へのリンクにするが、文そのものはリンクに
  # しない。長い文が丸ごと青くなると、何が押せるのか分からなくなる。
  def item_html(item, with_date)
    body = esc(item['text'])
    if item['href']
      body += %( <a class="news-go" href="#{esc(item['href'])}">#{JaNames.enabled? ? '見る' : 'Open'} →</a>)
    end
    date = with_date ? %(<time datetime="#{esc(item['date'])}">#{short_date(item['date'])}</time>) : ''
    %(<li>#{date}#{kind_chip(item['kind'])}<span class="news-text">#{body}</span></li>)
  end

  # 目次ページに差し込む塊。
  def recent_html(game)
    items = flat.first(RECENT)
    return '' if items.empty?

    ja = JaNames.enabled?
    <<~HTML
      <section class="news">
        <h2 class="news-title">#{ja ? '更新情報' : 'What is new'}<a class="news-all" href="/#{game}/changelog/">#{ja ? 'これまでの更新' : 'All updates'} →</a></h2>
        <ul class="news-list">#{items.map { |i| item_html(i, true) }.join}</ul>
      </section>
    HTML
  end

  # 全件のページ。
  def build_page(game)
    return nil if entries.empty?

    ja = JaNames.enabled?
    title = ja ? '更新履歴' : 'Changelog'
    total = flat.size

    days = entries.map { |day|
      list = (day['items'] || []).map { |i| item_html(i, false) }.join
      %(<section class="news-day"><h2>#{long_date(day['date'])}</h2>) +
        %(<ul class="news-list">#{list}</ul></section>)
    }.join

    lead =
      if ja
        "このサイトに加えた変更のうち、読む側から見えるものをまとめています。" \
        "全#{total}件。ゲーム本体の更新履歴ではありません。"
      else
        "Reader-visible changes to this site. #{total} entries."
      end

    <<~PAGE
      ---
      title: #{title}
      permalink: /#{game}/changelog/
      description: "ポケモンリボーン日本語攻略サイトの更新履歴。追加したページや直した不具合を日付順にまとめています。"
      ---

      <p id="title-text">#{title}</p>

      <p class="ref-back"><a href="/#{game}/">#{esc(JaNames.ui('Back to contents'))}</a></p>

      <p>#{esc(lead)}</p>

      #{days}
    PAGE
  end
end
