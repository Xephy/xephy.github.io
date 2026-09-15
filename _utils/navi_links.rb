# frozen_string_literal: true

require 'json'
require 'erb'

# 攻略本文の地名の見出しの下に、ナビ (/reborn/navi/) への1行を置く。
#
# ナビは目的地と進み具合だけを決めた状態で開き、出発地は読む人が選ぶ。
# 進み具合は「前の章まで終えた」。その時点ではまだ行けない場所 (その章で
# 初めて行く場所) は「その章まで終えた」。どちらでも道が1本も無い場所には置かない。
#
# 行けるかどうかは bin/navi-build が書き出した src/assets/navi/chN.json で決める
# (その場所に代表地点があり、そこへ着く道が1本以上あるか)。
module NaviLinks
  DATA_DIR = File.expand_path('../src/assets/navi', __dir__)
  HEADING = /\A\#\#[ \t]+(.+?)[ \t]*\{\#[^}]+\}[ \t]*\z/.freeze

  module_function

  # 章 (1〜) ごとに { 場所id => 着く道の数 }。代表地点の無い場所は入れない
  def reachable(ch)
    @reachable ||= {}
    return @reachable[ch] if @reachable.key?(ch)

    path = File.join(DATA_DIR, "ch#{ch}.json")
    @reachable[ch] = if File.exist?(path)
                       j = JSON.parse(File.read(path))
                       counts = Hash.new(0)
                       j['routes'].each_key { |k| counts[k.split('>', 2)[1]] += 1 }
                       j['places'].select { |p| p['label'] }.to_h { |p| [p['id'], counts[p['id']]] }
                     else
                       {}
                     end
  end

  # 日本語の地名 => 場所id。長い名前から照らす (「北オブシディア区」を「オブシディア区」より先に)
  def places
    @places ||= begin
      path = Dir[File.join(DATA_DIR, 'ch*.json')].max_by { |f| f[/ch(\d+)/, 1].to_i }
      path ? JSON.parse(File.read(path))['places'].to_h { |p| [p['name'], p['id']] } : {}
    end
  end

  def places_in(title)
    hits = places.keys.select { |n| title.include?(n) }
    hits.reject { |n| hits.any? { |o| o != n && o.include?(n) } }
        .sort_by { |n| title.index(n) }
  end

  # その見出しの場所へ案内するときの章。無ければ nil
  def chapter_for(num, id)
    [[num - 1, 1].max, num].uniq.find { |ch| reachable(ch).fetch(id, 0).positive? }
  end

  def link(game, ch, id, text)
    q = "p=ch#{ch}&to=#{ERB::Util.url_encode(id)}"
    %(<a href="/#{game}/navi/?#{ERB::Util.html_escape(q)}">#{ERB::Util.html_escape(text)}</a>)
  end

  def apply(text, game, type, num)
    return text unless game == 'reborn' && type == 'main'

    text.each_line.map { |line|
      m = line.chomp.match(HEADING)
      next line unless m

      found = places_in(m[1]).filter_map { |n| (ch = chapter_for(num, places[n])) && [n, ch] }
      next line if found.empty?

      body = if places_in(m[1]).length == 1
               link(game, found[0][1], places[found[0][0]], 'ナビでここへの道を調べる')
             else
               'ナビで道を調べる: ' + found.map { |n, ch| link(game, ch, places[n], n) }.join(' / ')
             end
      %(#{line.chomp}\n\n<p class="navi-link">#{body}</p>\n)
    }.join
  end
end
