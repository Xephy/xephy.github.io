# frozen_string_literal: true

# いま組み立てている本文の位置 (章と節)。
#
# 資料ページは「この行は本文のどこに載っていたか」を必要とするが、それが
# 分かるのは指示行を展開している最中だけ。出現表と戦闘表の両方が要るので、
# 受け渡しの場所を1つに決めておく。
#
# 章には通し番号も振る。出現場所ページの「ここまで進んだ」で使う。章の
# 題名 (「クリア後 エピソード3」など) からは進行の順序が読めないため。
module DocContext
  module_function

  def current
    @current
  end

  def current=(ctx)
    @current = ctx
  end

  # 1回の生成の最初に呼ぶ。通し番号ごと初期化する。
  def reset!
    @current = nil
    @chapters = []
  end

  # 章の切り替わり。同じ題名で2回呼ばれても番号は増やさない。
  def begin_chapter(title, slug = nil)
    @chapters ||= []
    @chapters << { title: title, slug: slug } unless @chapters.last && @chapters.last[:title] == title
    @chapters.length - 1
  end

  # 番号順の章の題名。絞り込みの選択肢を組むのに使う。
  def chapters
    (@chapters || []).map { |c| c[:title] }
  end

  # 「ここまで進んだ」の選択肢に使う章。付録は物語上の位置ではないので外す。
  # 資料が1件も無い章も残す。読者は自分がいる章を選ぶのであって、そこに
  # 資料があるかどうかは知らないため。
  def progress_chapters
    (@chapters || []).each_with_index
                     .reject { |c, _| c[:slug] == 'appendices' }
                     .map { |c, i| [i, c[:title]] }
  end

  def clear_position!
    @current = nil
  end
end
