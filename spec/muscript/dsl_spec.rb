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
