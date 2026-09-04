# frozen_string_literal: true

# 押して並べ替えられる表の見出し。わざ一覧と種族値ランキングで使う。
#
# 動かすのは myscripts.js の refSortTable で、data-sort の値と行の
# data-<値> を突き合わせて並べ替える。表ごとに書き分けると、印の付け方と
# 読み上げの属性が食い違うので、セルの組み立てはここ1つに集める。
module SortHeader
  module_function

  # label はエスケープ済みの文字列を渡すこと。
  #
  # 押せる場所はボタンにする。th ごと押せるようにすると、キーボードでも
  # 読み上げでも「押せるもの」として辿れない。
  #
  # on: を付けた列は、書き出した時点の並び。JavaScript が動かない環境でも
  # 表の並びと見出しの印が食い違わないようにするための指定。
  #
  # desc: false の列は昇順で書き出す列。図鑑番号のように小さいほうから読む
  # ものがこれで、他の列から戻ってきたときも昇順で並べたい。最初の一押しを
  # どちらにするかを data-sort-first で JavaScript へ伝える。
  def th(key, label, on: false, desc: true)
    dir = desc ? 'desc' : 'asc'
    aria = desc ? 'descending' : 'ascending'

    %(<th class="ref-sortable#{on ? " is-on is-#{dir}" : ''}" data-sort="#{key}" ) +
      (desc ? '' : %(data-sort-first="asc" )) +
      %(aria-sort="#{on ? aria : 'none'}">) +
      %(<button type="button" class="ref-sort">#{label}) +
      %(<span class="ref-arrow" aria-hidden="true"></span></button></th>)
  end
end
