module Muscript
  class Project
    TAIL_SECONDS = 0.5

    attr_reader :name, :tracks, :arrangement
    attr_accessor :bpm

    def initialize(name)
      @name = name
      @bpm = 120
      @tracks = []
      @arrangement = Arrangement.new
    end

    def add_track(track)
      @tracks << track
    end

    # section :intro, bars: 8
    # 書いた順に前のセクションの後ろへ並ぶ。トラックはこの名前を `at :intro` で引く。
    def add_section(name, bars: nil, beats: nil)
      @arrangement.add(name, bars:, beats:)
    end

    def section(name) = @arrangement.fetch(name)
    def sections = @arrangement.sections

    def samples_per_beat
      SAMPLE_RATE * 60.0 / @bpm
    end

    # 曲の長さは、鳴っている音の終わりと、書いたセクションの終わりの遅いほう。
    # 最後のセクションが無音でも、書いたぶんの尺は出す(構造がそのまま曲の長さ)。
    def arrangement_end_sample = Beats.samples(@arrangement.finish, bpm: @bpm)

    def render(path)
      total = [tracks.map(&:end_sample).max.to_i, arrangement_end_sample].max +
              (SAMPLE_RATE * TAIL_SECONDS).to_i
      left  = Array.new(total, 0.0)
      right = Array.new(total, 0.0)

      tracks.each do |t|
        g = t.gain_linear
        pl, pr = t.pan_gains
        bl, br = t.balance_gains
        gl = g * bl
        gr = g * br
        t.events.each do |e|
          at = e[:at]
          if (r = e[:right])
            # ステレオ素材は左右をそのまま流し、gainとバランスだけを掛ける
            l = e[:buf]
            l.each_index do |i|
              left[at + i]  += l[i] * gl
              right[at + i] += r[i] * gr
            end
          else
            e[:buf].each_with_index do |v, i|
              s = v * g
              left[at + i]  += s * pl
              right[at + i] += s * pr
            end
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
      puts format("%s | %d tracks%s | %.2fs | peak %.1f dBFS%s -> %s",
                  @name, tracks.length, sections_text, duration, peak_db,
                  peak > 0.99 ? " (normalized to -1dBFS)" : "", path)
      path
    end

    private

    # 構造を書いた曲だけ、いくつのセクションで組んだかを報告に足す。
    def sections_text
      @arrangement.empty? ? "" : format(" | %d sections", @arrangement.count)
    end
  end
end
