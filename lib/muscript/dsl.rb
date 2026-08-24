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

      # section :intro, bars: 8
      # 曲の構造。書いた順に前のセクションの後ろへ並ぶ(イントロ→ビルド→ドロップ)。
      # トラックはこの名前を `at :intro` で引くので、トラックより先に書く。
      def section(name, bars: nil, beats: nil)
        @project.add_section(name, bars:, beats:)
      end

      def track(name, &block)
        t = Track.new(name)
        dsl = TrackDSL.new(@project, t)
        dsl.instance_eval(&block)
        dsl.resolve_stems!
        @project.add_track(t)
      end
    end

    # トラックの中の「いま書いている場所」。`at` で切り替わる。
    # ひとつの at から次の at までがひと区切りで、そこに置いた audio と
    # slice / trim / loop はセットとして扱う。span はセクションの残りの長さ(拍)。
    class Placement
      attr_reader :start, :span, :stems, :edits

      def initialize(start: 0.0, span: nil)
        @start = start
        @span = span
        @stems = []
        @edits = []
      end
    end

    class TrackDSL
      def initialize(project, track)
        @project = project
        @track = track
        @placements = [Placement.new]
        @warp_to = nil
        @transpose = 0.0
      end

      # at :drop            :drop セクションの頭に置く
      # at :drop, bar: 3    :drop の3小節目
      # at bar: 17          17小節目(曲の頭から数える)
      #
      # ここから下に書いた audio / notes / pattern が、その場所に置かれる。
      # セクションを指したときは残りの長さも憶えるので、bars: を省いた pattern と
      # loop がその長さを埋める(セクションを16小節に伸ばせば、鳴るほうも伸びる)。
      def at(section = nil, bar: 1)
        offset = Beats.position(bar)
        return @placements << Placement.new(start: offset) if section.nil?

        found = @project.section(section)
        span = found.length - offset
        unless span.positive?
          raise ArgumentError,
                format("cannot start at bar %g of section %p: it is %g bars long",
                       bar, section, found.bars)
        end

        @placements << Placement.new(start: found.start + offset, span:)
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
        here.stems << stem
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

      # slice bars: 8, from: 5
      # 5小節目から8小節を切り出す。ここでいう小節は、そのステムが鳴っているテンポの小節
      # (warpしたなら曲のテンポ、warp: false なら素材のテンポ)。
      def slice(bars: nil, beats: nil, from: 1)
        here.edits << Edit.slice(bars:, beats:, from:)
      end

      # trim from: 3          頭の2小節を落として最後まで
      # trim from: 2, to: 6   2小節目から6小節目の手前まで(= 4小節)
      def trim(from: 1, to: nil)
        here.edits << Edit.trim(from:, to:)
      end

      # loop times: 4   4回鳴らす
      # loop bars: 16   16小節ぶんになるまで繰り返す(端は途中で切る)
      # loop            いま置いているセクションの残りを埋める(`at :drop` とセットで使う)
      # track ブロックの中の loop は Kernel#loop ではなくこちら。
      def loop(times: nil, bars: nil, beats: nil)
        here.edits << if times.nil? && bars.nil? && beats.nil?
                        Edit.fill(beats: fill_beats)
                      else
                        Edit.loop(times:, bars:, beats:)
                      end
      end

      # track ブロックを抜けたところで、ためたステムを読む。
      # warp_to / transpose はブロックのどこに書いても効くように、ここでまとめて適用する。
      # slice / trim / loop は `at` で区切ったひと区切りの設定で、書いた順に
      # その区切りのステム全部へ掛かる(区切りが無ければ、今までどおりトラック全体)。
      def resolve_stems!
        @placements.each do |placement|
          if placement.stems.empty? && placement.edits.any?
            raise ArgumentError,
                  "track #{@track.name.inspect} has no audio to slice / trim / loop (they do not apply to notes yet)"
          end

          placement.stems.each do |stem|
            clip = stem.resolve(project_bpm: @project.bpm, warp_to: @warp_to,
                                semitones: @transpose, edits: placement.edits)
            @track.add_stereo(samples(placement.start), clip.left, clip.right)
          end
        end
      end

      # notes %w[E2 _ G2 _], step: "1/8"
      # "_" は休符。時間は拍(beat)で計算し、サンプルへの変換は最後に一度だけ。
      def notes(list, step: "1/16")
        step_beats = parse_step(step)
        dur = (step_beats * @project.samples_per_beat * 0.9).round
        list.each_with_index do |n, i|
          next if n.nil? || n == "_"
          @track.add(samples(here.start + (i * step_beats)),
                     Synth.tone(@track.synth_shape, Note.freq(n), dur))
        end
      end

      # pattern bars: 2 do
      #   kick "x---------x-----"
      # end
      # 1行 = 1小節。文字数がその小節の分割数になる(16文字なら16分)。
      # `at :drop` の下で bars: を省くと、そのセクションを埋めるまで繰り返す。
      def pattern(bars: nil, &block)
        p = PatternDSL.new
        p.instance_eval(&block)
        limit = bars.nil? ? here.span : nil # 埋める時だけ、はみ出す音を落とす
        count = bars || fill_bars

        p.lines.each do |drum_name, steps|
          buf = Synth.drum(drum_name)
          divisions = steps.length
          count.times do |bar|
            steps.each_char.with_index do |ch, i|
              next unless ch == "x" || ch == "X"
              beat = (bar * Beats::PER_BAR) + (i * Beats::PER_BAR / divisions)
              next if limit && beat >= limit
              @track.add(samples(here.start + beat), buf)
            end
          end
        end
      end

      private

      # いま書いている場所。`at` を書いていなければ曲の頭(今までどおり)。
      def here = @placements.last

      # 拍 → サンプル。トラックの中で時間がサンプルになるのはここだけ。
      def samples(beats) = Beats.samples(beats, bpm: @project.bpm)

      # bars: を省いた pattern が何小節ぶん鳴るか。セクションの中なら、その長さを埋める。
      def fill_bars
        return 1 if here.span.nil?

        here.span.fdiv(Beats::PER_BAR).ceil
      end

      # bars: も times: も無い loop が、どこまで埋めるか。
      def fill_beats
        here.span ||
          raise(ArgumentError,
                "loop needs times: or bars: here (a bare loop fills the section put by `at :drop`)")
      end

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
