module Muscript
  # DSLは薄い糖衣に徹する。中身はぜんぶプレーンなオブジェクト(Project/Track)。
  module DSL
    class ProjectDSL
      def initialize(project)
        @project = project
      end

      def bpm(value)
        @project.bpm = value
      end

      def track(name, &block)
        t = Track.new(name)
        dsl = TrackDSL.new(@project, t)
        dsl.instance_eval(&block)
        dsl.resolve_stems!
        @project.add_track(t)
      end
    end

    class TrackDSL
      def initialize(project, track)
        @project = project
        @track = track
        @stems = []
        @warp_to = nil
        @transpose = 0.0
      end

      def synth(shape)
        @track.synth_shape = shape
      end

      def gain(db)
        @track.gain_db = db
      end

      def pan(value)
        @track.pan = value
      end

      # audio "stems/vocals.wav"
      # audio "stems/amen.wav", bpm: 140     # 素材のテンポ。プロジェクトのBPMに合わせて伸縮する
      # audio "stems/amen.wav", bpm: 140, warp: false  # テンポは覚えておくが、伸ばさない
      #
      # ステム(音声ファイル)をトラックの頭に置く。形式は問わない(ffmpegが読めるもの)。
      # 44.1kHz・ステレオへの変換はffmpeg任せで、Ruby側はバッファを受け取るだけ。
      # 実際に読むのは track ブロックを抜けた後。warp_to / transpose を先に集めてから、
      # 伸縮とピッチシフトをrubberbandに一度で渡すため。
      def audio(path, bpm: nil, warp: true)
        stem = Stem.new(path, bpm:, warp:)
        @stems << stem
        stem
      end

      # warp_to 87
      # 揃える先のテンポ。既定はプロジェクトのBPM。半分/倍のテンポで鳴らしたい時に使う。
      def warp_to(bpm)
        @warp_to = bpm
      end

      # transpose 2
      # ステムを半音単位でピッチシフトする(キー合わせ)。長さは変わらない。
      # 内蔵音源の notes には効かない(MIDI側のtransposeは #16)。
      def transpose(semitones)
        @transpose = semitones
      end

      # track ブロックを抜けたところで、ためたステムを読む。
      # warp_to / transpose はブロックのどこに書いても効くように、ここでまとめて適用する。
      def resolve_stems!
        @stems.each do |stem|
          clip = stem.resolve(project_bpm: @project.bpm, warp_to: @warp_to, semitones: @transpose)
          @track.add_stereo(0, clip.left, clip.right)
        end
      end

      # notes %w[E2 _ G2 _], step: "1/8"
      # "_" は休符。時間は拍(beat)で計算し、サンプルへの変換は最後に一度だけ。
      def notes(list, step: "1/16")
        step_beats = parse_step(step)
        list.each_with_index do |n, i|
          next if n.nil? || n == "_"
          at  = (i * step_beats * @project.samples_per_beat).round
          dur = (step_beats * @project.samples_per_beat * 0.9).round
          @track.add(at, Synth.tone(@track.synth_shape, Note.freq(n), dur))
        end
      end

      # pattern bars: 2 do
      #   kick "x---------x-----"
      # end
      # 1行 = 1小節。文字数がその小節の分割数になる(16文字なら16分)。
      def pattern(bars: 1, &block)
        p = PatternDSL.new
        p.instance_eval(&block)
        p.lines.each do |drum_name, steps|
          buf = Synth.drum(drum_name)
          divisions = steps.length
          bars.times do |bar|
            steps.each_char.with_index do |ch, i|
              next unless ch == "x" || ch == "X"
              beat = bar * 4.0 + i * 4.0 / divisions
              @track.add((beat * @project.samples_per_beat).round, buf)
            end
          end
        end
      end

      private

      def parse_step(step)
        m = step.to_s.match(%r{\A(\d+)/(\d+)\z})
        raise ArgumentError, "invalid step: #{step.inspect} (use e.g. \"1/8\")" unless m
        4.0 * m[1].to_i / m[2].to_i
      end
    end

    class PatternDSL
      attr_reader :lines

      def initialize
        @lines = []
      end

      def kick(steps)  = hit(:kick, steps)
      def snare(steps) = hit(:snare, steps)
      def hat(steps)   = hit(:hat, steps)

      def hit(drum_name, steps)
        @lines << [drum_name, steps]
      end
    end
  end
end
