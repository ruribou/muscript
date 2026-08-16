module Muscript
  class Project
    TAIL_SECONDS = 0.5

    attr_reader :name, :tracks
    attr_accessor :bpm

    def initialize(name)
      @name = name
      @bpm = 120
      @tracks = []
    end

    def add_track(track)
      @tracks << track
    end

    def samples_per_beat
      SAMPLE_RATE * 60.0 / @bpm
    end

    def render(path)
      total = tracks.map(&:end_sample).max.to_i + (SAMPLE_RATE * TAIL_SECONDS).to_i
      left  = Array.new(total, 0.0)
      right = Array.new(total, 0.0)

      tracks.each do |t|
        g = t.gain_linear
        pl, pr = t.pan_gains
        t.events.each do |e|
          at = e[:at]
          e[:buf].each_with_index do |v, i|
            s = v * g
            left[at + i]  += s * pl
            right[at + i] += s * pr
          end
        end
      end

      peak = 0.0
      left.each_index do |i|
        a = left[i].abs
        b = right[i].abs
        peak = a if a > peak
        peak = b if b > peak
      end
      if peak > 0.99
        # ヘッドルーム-1dBFSに収める。将来ここはマスターのlimiterに置き換わる
        scale = 0.891 / peak
        left.map!  { |v| v * scale }
        right.map! { |v| v * scale }
      end

      Wav.write(path, left, right)

      duration = total / SAMPLE_RATE.to_f
      peak_db = peak.zero? ? -Float::INFINITY : 20 * Math.log10(peak)
      puts format("%s | %d tracks | %.2fs | peak %.1f dBFS%s -> %s",
                  @name, tracks.length, duration, peak_db,
                  peak > 0.99 ? " (normalized to -1dBFS)" : "", path)
      path
    end
  end
end
