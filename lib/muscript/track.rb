module Muscript
  # トラック = イベント(開始サンプル位置, モノラルバッファ)の集まり + gain/pan。
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

    def end_sample
      @events.map { |e| e[:at] + e[:buf].length }.max || 0
    end

    def gain_linear
      10.0**(@gain_db / 20.0)
    end

    # 等パワーパン。pan: -1.0(L)..0.0..1.0(R)
    def pan_gains
      angle = (@pan + 1.0) * Math::PI / 4.0
      [Math.cos(angle), Math.sin(angle)]
    end
  end
end
