module Muscript
  # トラック = イベント(開始サンプル位置, バッファ)の集まり + gain/pan。
  # バッファはモノ(:buf)か、ステム由来のステレオ(:buf が左 / :right が右)。
  class Track
    attr_reader :name, :events
    attr_accessor :gain_db, :pan, :synth_shape

    def initialize(name)
      @name = name
      @events = []
      @gain_db = 0.0
      @pan = 0.0
      @synth_shape = :sine
    end

    def add(at_sample, buffer)
      @events << { at: at_sample, buf: buffer }
    end

    def add_stereo(at_sample, left, right)
      unless left.length == right.length
        raise ArgumentError, "stereo buffers must be the same length (#{left.length} vs #{right.length})"
      end

      @events << { at: at_sample, buf: left, right: right }
    end

    def end_sample
      @events.map { |e| e[:at] + e[:buf].length }.max || 0
    end

    def gain_linear
      10.0**(@gain_db / 20.0)
    end

    # モノ素材の定位。等パワーパン。pan: -1.0(L)..0.0..1.0(R)
    def pan_gains
      angle = (@pan + 1.0) * Math::PI / 4.0
      [Math.cos(angle), Math.sin(angle)]
    end

    # ステレオ素材の定位はバランス。センターでは素材の音量をそのまま通し、
    # 振った側の反対チャンネルを絞る(左右の広がりを潰さないため)。
    def balance_gains
      [@pan > 0 ? 1.0 - @pan : 1.0,
       @pan < 0 ? 1.0 + @pan : 1.0]
    end
  end
end
