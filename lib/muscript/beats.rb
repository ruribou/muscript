module Muscript
  # 音楽的な時間。小節と拍を「拍(beat)」という一本の物差しに揃えるところ。
  # サンプルに直すのは、素材のテンポが決まった最後の一回だけ(丸め誤差を溜めないため)。
  module Beats
    PER_BAR = 4.0 # 4/4だけを見る。拍子は将来

    module_function

    # 長さ。bars と beats は足し合わせる(bars: 1, beats: 2 なら6拍)。
    def length(bars: nil, beats: nil)
      raise ArgumentError, "give bars: or beats: (e.g. bars: 8)" if bars.nil? && beats.nil?

      value = (number(bars, :bars) * PER_BAR) + number(beats, :beats)
      unless value.positive?
        raise ArgumentError, "length must be positive: bars: #{bars.inspect}, beats: #{beats.inspect}"
      end

      value
    end

    # 位置。小節番号は1から数える(from: 5 は5小節目の頭)。5.5 なら5小節目の3拍目。
    def position(bar)
      value = number(bar, :bar)
      raise ArgumentError, "bar numbers start at 1: #{bar.inspect}" if value < 1.0

      (value - 1.0) * PER_BAR
    end

    # 拍 → サンプル。muscriptの中で音楽的な時間がサンプルになるのはここだけ。
    def samples(beats, bpm:, sample_rate: SAMPLE_RATE)
      raise ArgumentError, "bpm must be positive: #{bpm.inspect}" unless bpm.to_f.positive?

      (beats * 60.0 / bpm * sample_rate).round
    end

    # 拍 → 小節。「素材は4小節しかない」と言うために使う。
    def bars(beats) = beats / PER_BAR

    def number(value, name)
      return 0.0 if value.nil?
      raise ArgumentError, "#{name} must be a number: #{value.inspect}" unless value.is_a?(Numeric)

      value.to_f
    end
  end
end
