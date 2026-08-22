# frozen_string_literal: true

require_relative 'doc_context'

# ショップの逆引き。
#
# 本文の店の表は「この店に何があるか」しか答えられない。読者が知りたい
# のは逆で「このどうぐはどこで買えるか」「一番早く買えるのはどこか」。
#
# 実測で 85店 / 品目334 / のべ507件。うち71品目は2店以上で扱っている。
#
# 表を作り直すのではなく、ShopGetter が表を組む最中に1行ずつ受け取る。
# 画面に出るものと同じ値・同じ表記になる。
module ShopIndex
  module_function

  def entries
    @entries ||= []
  end

  def reset!
    @entries = []
  end

  def record(item:, shop:, price:)
    entries << { item: item, shop: shop, price: price, context: DocContext.current }
  end

  # どうぐごとにまとめる。並びは本文に出てくる順 = 早く買える順。
  def by_item
    order = []
    grouped = {}
    entries.each do |e|
      unless grouped.key?(e[:item])
        grouped[e[:item]] = []
        order << e[:item]
      end
      grouped[e[:item]] << e
    end
    order.map { |name| { item: name, shops: dedupe(grouped[name]) } }
  end

  # 同じ店を2回出さない。1つの店が本文の複数箇所に出ることがある。
  def dedupe(list)
    seen = {}
    list.each { |e| seen[[e[:shop], e.dig(:context, :href)]] ||= e }
    seen.values
  end
end
