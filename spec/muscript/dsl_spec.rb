RSpec.describe Muscript::DSL do
  describe "Muscript.project" do
    it "名前を持ったProjectを返す" do
      song = Muscript.project("My Song") { bpm 128 }

      expect(song).to be_a Muscript::Project
      expect(song.name).to eq "My Song"
      expect(song.bpm).to eq 128
    end

    it "書いた順にトラックを並べる" do
      song = Muscript.project("s") do
        track(:drums) {}
        track(:bass) {}
      end

      expect(song.tracks.map(&:name)).to eq %i[drums bass]
    end

    it "gain / pan / synth をトラックに渡す" do
      song = Muscript.project("s") do
        track :bass do
          synth :saw
          gain(-8)
          pan 0.25
        end
      end

      track = song.tracks.first
      expect(track.synth_shape).to eq :saw
      expect(track.gain_db).to eq(-8)
      expect(track.pan).to eq 0.25
    end
  end

  describe "section / at" do
    # 24小節の曲。イントロ8小節のあと、9小節目からドロップ16小節。
    def arranged(&block)
      Muscript.project("s") do
        bpm 120
        section :intro, bars: 8
        section :drop, bars: 16
        track(:t, &block)
      end
    end

    def bar(number) = ((number - 1) * 4 * 60.0 / 120 * Muscript::SAMPLE_RATE).round
    def positions(song) = song.tracks.first.events.map { |e| e[:at] }

    it "セクションを書いた順に並べる（ドロップは9小節目から）" do
      song = arranged { notes %w[E1] }

      expect(song.sections.map(&:name)).to eq %i[intro drop]
      expect(song.sections.map(&:start)).to eq [0.0, 32.0]
    end

    it "at を書かなければ、今までどおり曲の頭から鳴らす" do
      expect(positions(arranged { notes %w[E1] })).to eq [bar(1)]
    end

    it "at bar: で小節位置を指す（曲の頭から数える）" do
      expect(positions(arranged { at bar: 17; notes %w[E1] })).to eq [bar(17)]
    end

    it "at :drop でセクションの頭から鳴らす" do
      expect(positions(arranged { at :drop; notes %w[E1] })).to eq [bar(9)]
    end

    it "at :drop, bar: 3 でセクションの3小節目に置く" do
      expect(positions(arranged { at :drop, bar: 3; notes %w[E1] })).to eq [bar(11)]
    end

    it "パターンもセクションの頭から並ぶ" do
      song = arranged { at :drop; pattern(bars: 1) { kick "x-x-" } }

      expect(positions(song)).to eq [bar(9), bar(9.5)]
    end

    it "1本のトラックを複数のセクションに置ける" do
      song = arranged do
        at :intro
        notes %w[E1]
        at :drop
        notes %w[G1]
      end

      expect(positions(song)).to eq [bar(1), bar(9)]
    end

    it "bars: を省いたパターンは、セクションの長さを埋める" do
      song = arranged { at :drop; pattern { kick "x---" } }

      expect(positions(song).length).to eq 16 # ドロップの16小節ぶん
      expect(positions(song).first).to eq bar(9)
      expect(positions(song).last).to eq bar(24)
    end

    it "セクションの途中に置いたら、残りだけを埋める" do
      song = arranged { at :drop, bar: 13; pattern { kick "x---" } }

      expect(positions(song)).to eq [bar(21), bar(22), bar(23), bar(24)]
    end

    it "bars: を書いたら、セクションの中でもそのぶんだけ鳴らす" do
      song = arranged { at :drop; pattern(bars: 2) { kick "x---" } }

      expect(positions(song)).to eq [bar(9), bar(10)]
    end

    it "セクションからはみ出す音は鳴らさない（埋めるとき）" do
      song = Muscript.project("s") do
        bpm 120
        section :half, beats: 6 # 1.5小節
        track(:t) { at :half; pattern { kick "xxxx" } } # 1拍ごと
      end

      expect(song.tracks.first.events.length).to eq 6 # 6拍ぶんで止まる
    end

    it "セクションの外では、bars: を省いたパターンは1小節だけ鳴らす" do
      song = arranged { at bar: 5; pattern { kick "x---" } }

      expect(positions(song)).to eq [bar(5)]
    end

    it "知らないセクションを指したら、知っている名前を添えて落ちる" do
      expect { arranged { at :build } }
        .to raise_error(ArgumentError, "unknown section :build (known sections: :intro, :drop)")
    end

    it "セクションを書く前に at で指したら、どこに書くかを教えて落ちる" do
      expect { Muscript.project("s") { track(:t) { at :drop } } }
        .to raise_error(ArgumentError, /sections are declared before the tracks/)
    end

    it "セクションからはみ出す位置を指したら、セクションの長さを添えて落ちる" do
      expect { arranged { at :intro, bar: 9 } }
        .to raise_error(ArgumentError, "cannot start at bar 9 of section :intro: it is 8 bars long")
    end

    it "同じ名前のセクションを二度書いたら落ちる" do
      expect { Muscript.project("s") { section :intro, bars: 8; section :intro, bars: 4 } }
        .to raise_error(ArgumentError, "section :intro is already defined")
    end

    it "セクションの外で長さの無い loop を書いたら、何を書けばいいか教えて落ちる" do
      expect { arranged { audio "stems/nope.wav"; loop } }
        .to raise_error(ArgumentError, /loop needs times: or bars: here/)
    end
  end

  describe "notes" do
    def bass_events(list, step: "1/16", tempo: 120)
      Muscript.project("s") do
        bpm tempo
        track(:bass) { notes list, step: }
      end.tracks.first.events
    end

    it "音の数だけイベントを作る" do
      expect(bass_events(%w[E1 G1 A1]).length).to eq 3
    end

    it "\"_\" と nil を休符にする" do
      expect(bass_events(["E1", "_", nil, "G1"]).length).to eq 2
    end

    it "stepの間隔で等間隔に並べる（120BPMの1/8 = 11025サンプル）" do
      events = bass_events(%w[E1 E1 E1], step: "1/8")
      expect(events.map { |e| e[:at] }).to eq [0, 11_025, 22_050]
    end

    it "休符ぶんの時間は空ける（詰めない）" do
      events = bass_events(["E1", "_", "G1"], step: "1/8")
      expect(events.map { |e| e[:at] }).to eq [0, 22_050]
    end

    it "音の長さはstepの90%にする（次の音との隙間）" do
      events = bass_events(%w[E1], step: "1/8")
      expect(events.first[:buf].length).to eq 9923 # 11025 * 0.9
    end

    it "BPMが上がると間隔が詰まる" do
      at174 = bass_events(%w[E1 E1], step: "1/8", tempo: 174).last[:at]
      at120 = bass_events(%w[E1 E1], step: "1/8", tempo: 120).last[:at]
      expect(at174).to be < at120
      expect(at174).to eq 7603 # 15206.9 * 0.5
    end

    it "1/4は1/8の倍の間隔になる" do
      quarter = bass_events(%w[E1 E1], step: "1/4").last[:at]
      eighth  = bass_events(%w[E1 E1], step: "1/8").last[:at]
      expect(quarter).to eq eighth * 2
    end

    it "指定した波形と音高で鳴らす" do
      song = Muscript.project("s") do
        bpm 120
        track :bass do
          synth :saw
          notes %w[E1], step: "1/8"
        end
      end

      expect(song.tracks.first.events.first[:buf])
        .to eq Muscript::Synth.tone(:saw, Muscript::Note.freq("E1"), 9923)
    end

    it "読めないstepを拒否する" do
      ["1-8", "8", "1/", "eighth"].each do |bad|
        expect { bass_events(%w[E1], step: bad) }
          .to raise_error(ArgumentError, /invalid step/), "#{bad.inspect} が通ってしまった"
      end
    end

    it "読めない音名を拒否する" do
      expect { bass_events(%w[H1]) }.to raise_error(ArgumentError, /invalid note name/)
    end
  end

  describe "audio", :ffmpeg do
    # 素材の代わりに、muscript自身が書いたWAVをステムとして読ませる。
    def with_stem(left, right = left)
      in_tmpdir do |dir|
        yield Muscript::Wav.write(File.join(dir, "stem.wav"), left, right)
      end
    end

    it "ステムを頭に1イベントとして置く" do
      with_stem(sine(440, 0.1)) do |path|
        song = Muscript.project("s") { track(:vocals) { audio path } }
        events = song.tracks.first.events

        expect(events.length).to eq 1
        expect(events.first[:at]).to eq 0
        expect(events.first[:buf].length).to eq (Muscript::SAMPLE_RATE * 0.1).to_i
      end
    end

    it "左右を別のバッファとして持つ" do
      with_stem(sine(440, 0.1, amplitude: 0.5), sine(440, 0.1, amplitude: 0.25)) do |path|
        event = Muscript.project("s") { track(:vocals) { audio path } }.tracks.first.events.first

        expect(event[:buf].map(&:abs).max).to be_within(0.001).of(0.5)
        expect(event[:right].map(&:abs).max).to be_within(0.001).of(0.25)
      end
    end

    it "gain / pan と組み合わせられる" do
      with_stem(sine(440, 0.1)) do |path|
        song = Muscript.project("s") do
          track :vocals do
            audio path
            gain(-6)
            pan 0.5
          end
        end

        expect(song.tracks.first.gain_db).to eq(-6)
        expect(song.tracks.first.balance_gains).to eq [0.5, 1.0]
      end
    end

    it "読み込んだステムを返す（長さを見たい時のため）" do
      with_stem(sine(440, 0.25)) do |path|
        stem = nil
        Muscript.project("s") { track(:vocals) { stem = audio path } }

        expect(stem.clip.duration).to be_within(0.001).of(0.25)
      end
    end

    it "無いファイルを拒否する" do
      expect { Muscript.project("s") { track(:vocals) { audio "stems/nope.wav" } } }
        .to raise_error(Muscript::Audio::Error, /audio file not found/)
    end
  end

  describe "warp_to / transpose", :ffmpeg do
    # 素材の代わり。1小節ぶんのサイン波を、指定のテンポで書く。
    def with_loop(bpm, bars: 1, freq: 440, name: "loop")
      in_tmpdir do |dir|
        wave = sine(freq, bars * 4 * 60.0 / bpm)
        yield Muscript::Wav.write(File.join(dir, "#{name}.wav"), wave, wave), wave.length
      end
    end

    def stem_length(song) = song.tracks.first.events.first[:buf].length

    it "bpm: を渡さなければ、今までどおりそのまま鳴らす" do
      with_loop(140) do |path|
        song = Muscript.project("s") { bpm 174; track(:loop) { audio path } }

        expect(stem_length(song)).to eq (4 * 60.0 / 140 * Muscript::SAMPLE_RATE).round
      end
    end

    describe "揃える", :rubberband do
      it "bpm: を渡すと、プロジェクトのBPMに合わせて伸び縮みする" do
        with_loop(140) do |path|
          song = Muscript.project("s") { bpm 174; track(:loop) { audio path, bpm: 140 } }

          expect(stem_length(song)).to eq (4 * 60.0 / 174 * Muscript::SAMPLE_RATE).round
        end
      end

      it "BPMの違うループ2本が、同じ小節数で同じ長さに揃う" do
        in_tmpdir do |dir|
          a = Muscript::Wav.write(File.join(dir, "a.wav"), *([sine(440, 2 * 4 * 60.0 / 140)] * 2))
          b = Muscript::Wav.write(File.join(dir, "b.wav"), *([sine(330, 2 * 4 * 60.0 / 90)] * 2))

          song = Muscript.project("s") do
            bpm 174
            track(:a) { audio a, bpm: 140 }
            track(:b) { audio b, bpm: 90 }
          end

          lengths = song.tracks.map { |t| t.events.first[:buf].length }
          expect(lengths.uniq.length).to eq 1
          expect(lengths.first).to be_within(1).of(2 * 4 * 60.0 / 174 * Muscript::SAMPLE_RATE)
        end
      end

      it "warp: false なら、テンポを覚えたまま伸ばさない" do
        with_loop(140) do |path|
          song = Muscript.project("s") { bpm 174; track(:loop) { audio path, bpm: 140, warp: false } }

          expect(stem_length(song)).to eq (4 * 60.0 / 140 * Muscript::SAMPLE_RATE).round
        end
      end

      it "warp_to で揃え先を上書きできる（半テン）" do
        with_loop(140) do |path|
          song = Muscript.project("s") do
            bpm 174
            track(:loop) do
              audio path, bpm: 140
              warp_to 87
            end
          end

          expect(stem_length(song)).to eq (4 * 60.0 / 87 * Muscript::SAMPLE_RATE).round
        end
      end

      it "warp_to / transpose は audio より前に書いても効く" do
        with_loop(140) do |path|
          song = Muscript.project("s") do
            bpm 174
            track(:loop) do
              warp_to 87
              audio path, bpm: 140
            end
          end

          expect(stem_length(song)).to eq (4 * 60.0 / 87 * Muscript::SAMPLE_RATE).round
        end
      end

      it "warp_to を書いたのに素材のテンポが無ければ落ちる" do
        with_loop(140) do |path|
          expect { Muscript.project("s") { bpm 174; track(:loop) { audio path; warp_to 87 } } }
            .to raise_error(ArgumentError, /warp_to 87 needs the source tempo/)
        end
      end
    end

    describe "transpose", :rubberband do
      it "半音単位で音の高さを動かす（長さはそのまま）" do
        with_loop(174, freq: 440) do |path, frames|
          song = Muscript.project("s") do
            bpm 174
            track(:loop) do
              audio path
              transpose 12
            end
          end

          event = song.tracks.first.events.first
          expect(event[:buf].length).to eq frames
          expect(amplitude_at(event[:buf], 880)).to be > 0.3
          expect(amplitude_at(event[:buf], 440)).to be < 0.05
        end
      end

      it "transpose 0 なら rubberband を呼ばない" do
        with_loop(174, freq: 440) do |path|
          stub_const("Muscript::Warp::RUBBERBAND", "muscript-no-such-rubberband")
          song = Muscript.project("s") { bpm 174; track(:loop) { audio path; transpose 0 } }

          expect(amplitude_at(song.tracks.first.events.first[:buf], 440)).to be > 0.3
        end
      end

      it "伸縮とピッチシフトは同じトラックで一緒に掛けられる" do
        with_loop(140, freq: 440) do |path|
          song = Muscript.project("s") do
            bpm 174
            track(:loop) do
              audio path, bpm: 140
              transpose 12
            end
          end

          event = song.tracks.first.events.first
          expect(event[:buf].length).to eq (4 * 60.0 / 174 * Muscript::SAMPLE_RATE).round
          expect(amplitude_at(event[:buf], 880)).to be > 0.3
        end
      end
    end
  end

  describe "slice / trim / loop", :ffmpeg do
    # 位置がそのまま値になっている素材(-1.0から+1.0へ上がるだけの波形)。
    # どこを切り出したかが、切り口の値で分かる。
    def with_ramp(bars:, tempo: 174)
      in_tmpdir do |dir|
        frames = (bars * 4 * 60.0 / tempo * Muscript::SAMPLE_RATE).round
        wave = Array.new(frames) { |i| (2.0 * i / frames) - 1.0 }
        yield Muscript::Wav.write(File.join(dir, "ramp.wav"), wave, wave), frames
      end
    end

    def clip(song) = song.tracks.first.events.first[:buf]

    def bar_frames(bars, tempo: 174) = (bars * 4 * 60.0 / tempo * Muscript::SAMPLE_RATE).round

    it "指定した小節から、指定した小節数だけ切り出す" do
      with_ramp(bars: 4) do |path|
        song = Muscript.project("s") do
          bpm 174
          track(:loop) { audio path; slice bars: 2, from: 3 }
        end

        expect(clip(song).length).to eq bar_frames(2)
        expect(clip(song).first).to be_within(0.001).of(0.0) # 素材のちょうど半分の位置
      end
    end

    it "loop times: で繰り返す" do
      with_ramp(bars: 2) do |path, frames|
        song = Muscript.project("s") do
          bpm 174
          track(:loop) { audio path; loop times: 4 }
        end

        expect(clip(song).length).to eq frames * 4
        expect(clip(song)[frames]).to eq clip(song).first # 頭に戻っている
      end
    end

    it "loop bars: で長さを埋める" do
      with_ramp(bars: 2) do |path|
        song = Muscript.project("s") do
          bpm 174
          track(:loop) { audio path; loop bars: 7 }
        end

        expect(clip(song).length).to eq bar_frames(7)
      end
    end

    it "trim で区間を切り出す" do
      with_ramp(bars: 4) do |path|
        song = Muscript.project("s") do
          bpm 174
          track(:loop) { audio path; trim from: 2, to: 4 }
        end

        expect(clip(song).length).to eq bar_frames(2)
        expect(clip(song).first).to be_within(0.001).of(-0.5) # 素材の1/4の位置
      end
    end

    it "書いた順に掛かる（切ってから繰り返す）" do
      with_ramp(bars: 4) do |path|
        song = Muscript.project("s") do
          bpm 174
          track :loop do
            audio path
            slice bars: 1, from: 2
            loop times: 3
          end
        end

        expect(clip(song).length).to eq bar_frames(1) * 3 # 1小節の切り出しが3つ
        expect(clip(song)[bar_frames(1)]).to eq clip(song).first
      end
    end

    it "同じトラックのステム全部に掛かる" do
      with_ramp(bars: 4) do |path|
        song = Muscript.project("s") do
          bpm 174
          track :loop do
            audio path
            audio path
            slice bars: 1
          end
        end

        expect(song.tracks.first.events.map { |e| e[:buf].length }).to eq [bar_frames(1)] * 2
      end
    end

    it "warp: false なら素材のテンポの小節で切る" do
      with_ramp(bars: 4, tempo: 140) do |path|
        song = Muscript.project("s") do
          bpm 174
          track(:loop) { audio path, bpm: 140, warp: false; slice bars: 2 }
        end

        expect(clip(song).length).to eq bar_frames(2, tempo: 140)
      end
    end

    it "揃えたあとの小節で切る（切るのは伸ばした後）", :rubberband do
      with_ramp(bars: 4, tempo: 140) do |path|
        song = Muscript.project("s") do
          bpm 174
          track(:loop) { audio path, bpm: 140; slice bars: 2 }
        end

        expect(clip(song).length).to eq bar_frames(2)
      end
    end

    it "at で区切ると、slice / loop はその区切りのステムだけに掛かる" do
      with_ramp(bars: 4) do |path|
        song = Muscript.project("s") do
          bpm 174
          section :intro, bars: 4
          section :drop, bars: 4
          track :loop do
            at :intro
            audio path
            slice bars: 1
            at :drop
            audio path
            slice bars: 2
          end
        end

        events = song.tracks.first.events
        expect(events.map { |e| e[:buf].length }).to eq [bar_frames(1), bar_frames(2)]
        expect(events.map { |e| e[:at] }).to eq [0, bar_frames(4)] # ドロップは5小節目
      end
    end

    it "loop（長さ指定なし）でセクションの残りを埋める" do
      with_ramp(bars: 2) do |path|
        song = Muscript.project("s") do
          bpm 174
          section :drop, bars: 7
          track :loop do
            at :drop
            audio path
            loop
          end
        end

        expect(clip(song).length).to eq bar_frames(7)
      end
    end

    it "セクションの途中からなら、残りだけを埋める" do
      with_ramp(bars: 2) do |path|
        song = Muscript.project("s") do
          bpm 174
          section :drop, bars: 8
          track :loop do
            at :drop, bar: 3
            audio path
            loop
          end
        end

        expect(clip(song).length).to eq bar_frames(6)
      end
    end

    it "セクションを埋める loop は曲の小節で数える（素材が半分のテンポで鳴っていても）" do
      with_ramp(bars: 4, tempo: 87) do |path|
        song = Muscript.project("s") do
          bpm 174
          section :drop, bars: 8
          track :loop do
            at :drop
            audio path, bpm: 87, warp: false
            loop
          end
        end

        # 曲の8小節ぶん。素材の小節(87BPM)で数えていたら倍の長さになる
        expect(clip(song).length).to eq bar_frames(8)
      end
    end

    it "ステムの無い区切りで slice を書いたら落ちる" do
      with_ramp(bars: 4) do |path|
        expect do
          Muscript.project("s") do
            bpm 174
            section :intro, bars: 4
            section :drop, bars: 4
            track :loop do
              at :intro
              audio path
              at :drop
              slice bars: 1
            end
          end
        end.to raise_error(ArgumentError, /track :loop has no audio to slice \/ trim \/ loop/)
      end
    end

    it "ステムの無いトラックで使ったら、まだ効かないと教えて落ちる" do
      expect { Muscript.project("s") { track(:bass) { notes %w[E1]; loop times: 4 } } }
        .to raise_error(ArgumentError, /track :bass has no audio to slice \/ trim \/ loop/)
    end

    it "素材より長く切ろうとしたら、素材の長さを教えて落ちる" do
      with_ramp(bars: 4) do |path|
        expect { Muscript.project("s") { bpm 174; track(:loop) { audio path; slice bars: 8 } } }
          .to raise_error(ArgumentError, /cannot cut 8 bars from bar 1: .+ is 4 bars at 174 BPM/)
      end
    end
  end

  describe "pattern" do
    def drum_events(bars: 1, tempo: 120, &block)
      Muscript.project("s") do
        bpm tempo
        track(:drums) { pattern(bars:, &block) }
      end.tracks.first.events
    end

    it "\"x\" の位置だけ鳴らす" do
      events = drum_events { kick "x---------x-----" }
      expect(events.map { |e| e[:at] }).to eq [0, 55_125] # 0拍目と2.5拍目
    end

    it "大文字の \"X\" も鳴らす" do
      expect(drum_events { kick "X---" }.length).to eq 1
    end

    it "\"x\" 以外の文字は休符として扱う" do
      expect(drum_events { hat "x.-_x" }.length).to eq 2
    end

    it "1行の文字数をその小節の分割数にする" do
      quarters = drum_events { kick "xxxx" }
      expect(quarters.map { |e| e[:at] }).to eq [0, 22_050, 44_100, 66_150]
    end

    it "barsの回数だけ繰り返す" do
      events = drum_events(bars: 2) { kick "x---------x-----" }
      expect(events.map { |e| e[:at] }).to eq [0, 55_125, 88_200, 143_325]
    end

    it "複数のドラムを重ねる（行ごとに分割数は独立）" do
      events = drum_events do
        kick  "x---------x-----"
        snare "----x-------x---"
        hat   "x-x-x-x-"
      end

      expect(events.length).to eq 2 + 2 + 4
      expect(events.map { |e| e[:buf].length }.uniq.length).to eq 3
    end

    it "同じドラムのバッファを共有する（毎回合成しない）" do
      buffers = drum_events { kick "x-x-" }.map { |e| e[:buf] }
      expect(buffers.first).to be buffers.last
      expect(buffers.first).to be Muscript::Synth.drum(:kick)
    end

    it "知らないドラムを拒否する" do
      expect { drum_events { hit(:cowbell, "x---") } }
        .to raise_error(ArgumentError, /unknown drum/)
    end
  end
end
