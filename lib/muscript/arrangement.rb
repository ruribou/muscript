module Muscript
  # 曲の一区切り。始まる位置(start)も長さ(length)も拍で持つ。
  Section = Data.define(:name, :start, :length) do
    def finish = start + length
    def bars = Beats.bars(length)
  end

  # 曲の構造。セクションは書いた順に、前のセクションの後ろへ並ぶ。
  # ここが曲の物差しになる: トラックの `at :drop` はこの並びを引くだけ。
  class Arrangement
    def initialize
      @sections = {}
    end

    def sections = @sections.values
    def count    = @sections.length
    def empty?   = @sections.empty?

    # 曲の終わり(拍)。セクションは隙間なく並ぶので、長さの合計がそのまま終わりになる。
    def finish = sections.sum(0.0, &:length)

    def add(name, bars: nil, beats: nil)
      raise ArgumentError, "section #{name.inspect} is already defined" if @sections.key?(name)

      @sections[name] = Section.new(name:, start: finish, length: Beats.length(bars:, beats:))
    end

    def fetch(name)
      @sections.fetch(name) { raise ArgumentError, "unknown section #{name.inspect} (#{known})" }
    end

    private

    # 知らないセクションを指された時に、何を書けばいいかを添えるための一言。
    def known
      return "sections are declared before the tracks: section :intro, bars: 8" if empty?

      "known sections: #{@sections.keys.map(&:inspect).join(", ")}"
    end
  end
end
