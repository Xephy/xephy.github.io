# frozen_string_literal: true

require_relative 'ja_names'

# 章の読み順には入らない資料ページの一覧。
#
# 動線 (章ナビ・目次ページ・トップ・一枚版の見出し) が4箇所あるので、
# 定義はここ1つに集める。ページを足すときは PAGES に1行足すだけでよい。
module ReferencePages
  module_function

  PAGES = [
    { slug: 'affinity', label: '好感度まとめ', en: 'Relationship Points',
      desc: '人物ごとの選択肢と増減' }
  ].freeze

  def all
    PAGES
  end

  def label(page)
    JaNames.enabled? ? page[:label] : page[:en]
  end

  def path(game, page)
    "/#{game}/#{page[:slug]}/"
  end

  # 章ナビや目次ページに置く <li> の並び。
  def list_items(game)
    all.map { |p| %(<li><a href="#{path(game, p)}">#{label(p)}</a></li>) }
  end
end
