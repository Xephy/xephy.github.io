# frozen_string_literal: true

require_relative 'ja_names'

# ネタバレの開閉ボタンを整える。
#
# 生の原稿では <a display="initial" class="spoilerBtn" type="button"> という
# 形で書かれている。display と type は <a> では何の意味も持たない残骸で、
# href が無いのでキーボードの操作対象にもならなかった。
#
# ここで role と tabindex を補い、開いたあと閉じ直すためのラベルを渡す。
# ラベルを JavaScript に直接書かないのは、対訳表 (_ja/ui.yml) が Jekyll の
# source (src/) の外にあって Liquid からは読めず、訳の管理を1箇所に
# 保ちたいため。
module Spoiler
  module_function

  OPEN_TAG = /<a\s+([^>]*\bclass="spoilerBtn"[^>]*)>/.freeze
  DEAD_ATTRS = [/\s*display="[^"]*"/, /\s*type="button"/, /\s*title="[^"]*"/].freeze

  def apply(content)
    content.to_s.gsub(OPEN_TAG) do
      attrs = Regexp.last_match(1)
      DEAD_ATTRS.each { |re| attrs = attrs.gsub(re, '') }
      %(<a #{attrs.strip} role="button" tabindex="0" ) +
        %(title="#{JaNames.ui('Click to reveal')}" data-hide="#{JaNames.ui('Hide again')}">)
    end
  end
end
