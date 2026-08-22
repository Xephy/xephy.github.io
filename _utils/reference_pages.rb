# frozen_string_literal: true

require_relative 'ja_names'

# 章の読み順には入らない資料ページの一覧。
#
# 動線 (章ナビ・目次ページ・トップ・一枚版の見出し) が4箇所あるので、
# 定義はここ1つに集める。ページを足すときは PAGES に1行足すだけでよい。
module ReferencePages
  module_function

  PAGES = [
    { slug: 'pokemon', label: 'ポケモンの出現場所', en: 'Wild Encounters' },
    { slug: 'shops', label: 'どうぐの買える店', en: 'Shop Index' },
    { slug: 'tms', label: 'わざマシン一覧', en: 'TM & HM List' },
    { slug: 'fields', label: 'フィールド効果', en: 'Field Effects' },
    { slug: 'affinity', label: '好感度まとめ', en: 'Relationship Points' }
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
