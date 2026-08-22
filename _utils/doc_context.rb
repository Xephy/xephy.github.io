# frozen_string_literal: true

# いま組み立てている本文の位置 (章と節)。
#
# 資料ページは「この行は本文のどこに載っていたか」を必要とするが、それが
# 分かるのは指示行を展開している最中だけ。出現表と戦闘表の両方が要るので、
# 受け渡しの場所を1つに決めておく。
module DocContext
  module_function

  def current
    @current
  end

  def current=(ctx)
    @current = ctx
  end

  def reset!
    @current = nil
  end
end
