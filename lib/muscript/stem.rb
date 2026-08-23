module Muscript
  # `audio` に渡された素材ひとつ。
  # 「このファイルは140BPM」という素材側の事実と、「曲は174BPM」という曲側の都合を
  # 突き合わせて、そのまま鳴らせるClipにするところ。伸ばす仕事そのものは Warp(rubberband)。
  class Stem
    attr_reader :path, :bpm, :clip

    def initialize(path, bpm: nil, warp: true)
      raise ArgumentError, "bpm must be positive: #{bpm.inspect}" if bpm && !bpm.to_f.positive?

      @path = path
      @bpm = bpm
      @warp = warp
      @clip = nil
    end

    def warp? = @warp

    # 素材を to_bpm(既定はプロジェクトのBPM)に揃え、semitones だけピッチを動かして読む。
    # 伸縮もピッチも要らない時は、素材をそのまま読むだけでrubberbandは走らない。
    def resolve(project_bpm:, warp_to: nil, semitones: 0.0)
      @clip = Audio.load(Warp.process(@path, time_ratio: time_ratio(project_bpm, warp_to),
                                             semitones: semitones))
    end

    private

    def time_ratio(project_bpm, warp_to)
      return 1.0 unless @warp

      target = warp_to || project_bpm
      if @bpm.nil?
        # 自動(warp_toなし)なら黙ってそのまま鳴らす。明示された時だけ、足りないものを教える。
        raise ArgumentError, "warp_to #{target} needs the source tempo: audio #{@path.inspect}, bpm: 140" if warp_to

        return 1.0
      end

      Warp.ratio(from: @bpm, to: target)
    end
  end
end
