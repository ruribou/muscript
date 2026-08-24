module Muscript
  # クリップ操作(slice / trim / loop)。
  # DSLに書いた時点で拍に翻訳して憶えておき、サンプルに直すのは素材のテンポが決まってから。
  # ここでいう「小節」は、そのクリップが鳴っているテンポの小節(warp後なら揃えた先のテンポ)。
  module Edit
    # 数サンプルの不足は黙って詰める。伸縮の丸めで1サンプルずれることがあるため(0.05ms未満)。
    SLACK = 2

    module_function

    # slice bars: 8, from: 5   5小節目から8小節
    def slice(bars: nil, beats: nil, from: 1)
      Cut.new(from: Beats.position(from), length: Beats.length(bars:, beats:))
    end

    # trim from: 3          3小節目から最後まで(頭を落とす)
    # trim from: 2, to: 6   2小節目から6小節目の手前まで(= 4小節)
    def trim(from: 1, to: nil)
      start = Beats.position(from)
      return Cut.new(from: start, length: nil) if to.nil?

      length = Beats.position(to) - start
      raise ArgumentError, "trim to: #{to.inspect} must come after from: #{from.inspect}" unless length.positive?

      Cut.new(from: start, length:)
    end

    # loop times: 4   4回鳴らす(= 4倍の長さ)
    # loop bars: 16   16小節ぶんになるまで繰り返す(端は途中で切る)
    def loop(times: nil, bars: nil, beats: nil)
      raise ArgumentError, "give loop times: or bars:, not both" if times && (bars || beats)
      return Repeat.new(times: count(times), length: nil) if times

      Repeat.new(times: nil, length: Beats.length(bars:, beats:))
    end

    def count(times)
      return times if times.is_a?(Integer) && times >= 1

      raise ArgumentError, "loop times: must be an integer >= 1: #{times.inspect}"
    end

    # 「その操作は素材に対して長すぎる」と、素材の実際の長さを添えて言う。
    def too_short(what, clip, bpm)
      format("cannot %s: %s is %s bars at %g BPM", what, clip.path, bars_text(clip.beats(bpm:)), bpm)
    end

    def bar_number(beats) = bars_text(beats + Beats::PER_BAR)

    # メッセージ用の小節数。デコードの端数で 3.99999 と出さない程度に丸める。
    def bars_text(beats) = format("%.4g", Beats.bars(beats))

    # 切り出し。from(拍)から length(拍)ぶん。length が nil なら素材の終わりまで。
    # 長さは「頼まれた拍数ちょうど」にする。切り出す場所が変わっても長さが1サンプル揺れないので、
    # 繰り返しても曲のグリッドからずれない(切り出し位置の丸めは素材を読む側だけの話にする)。
    Cut = Data.define(:from, :length) do
      def apply(clip, bpm:)
        at = Beats.samples(from, bpm:, sample_rate: clip.sample_rate)
        raise ArgumentError, Edit.too_short("start at bar #{Edit.bar_number(from)}", clip, bpm) if at >= clip.length

        count = length.nil? ? clip.length - at : Beats.samples(length, bpm:, sample_rate: clip.sample_rate)
        if at + count > clip.length + SLACK
          wanted = format("cut %s bars from bar %s", Edit.bars_text(length), Edit.bar_number(from))
          raise ArgumentError, Edit.too_short(wanted, clip, bpm)
        end

        clip.cut(at, count)
      end
    end

    # 繰り返し。times 回、または length(拍)ぶんになるまで。
    Repeat = Data.define(:times, :length) do
      def apply(clip, bpm:)
        total = if times
                  clip.length * times
                else
                  Beats.samples(length, bpm:, sample_rate: clip.sample_rate)
                end

        clip.repeat(total)
      end
    end
  end
end
