RSpec.describe Muscript::Warp do
  # 伸ばす前の素材。muscript自身が書いたWAVを使う。
  def with_source(seconds: 1.0, freq: 440, &)
    in_tmpdir do |dir|
      wave = sine(freq, seconds)
      yield Muscript::Wav.write(File.join(dir, "src.wav"), wave, wave), dir
    end
  end

  def frames(path) = Muscript::Audio.load(path).length

  describe ".ratio" do
    it "素材のBPMを揃え先のBPMで割った長さの倍率を返す" do
      expect(described_class.ratio(from: 140, to: 174)).to eq(140 / 174.0)
    end

    it "同じテンポなら等倍" do
      expect(described_class.ratio(from: 174, to: 174)).to eq 1.0
    end

    it "速くするなら1より小さい / 遅くするなら1より大きい" do
      expect(described_class.ratio(from: 140, to: 174)).to be < 1.0
      expect(described_class.ratio(from: 140, to: 87)).to be > 1.0
    end

    it "0以下のBPMは受け取らない" do
      expect { described_class.ratio(from: 0, to: 174) }.to raise_error(described_class::Error, /invalid bpm/)
      expect { described_class.ratio(from: 140, to: -1) }.to raise_error(described_class::Error, /invalid bpm/)
    end
  end

  describe ".process" do
    it "等倍・ピッチそのままなら、rubberbandを呼ばずに素材をそのまま返す" do
      with_source do |path|
        stub_const("Muscript::Warp::RUBBERBAND", "muscript-no-such-rubberband")

        expect(described_class.process(path)).to eq path
        expect(described_class.process(path, time_ratio: 1.0, semitones: 0)).to eq path
      end
    end

    it "無いファイルは伸ばす前に落とす" do
      expect { described_class.process("stems/nope.wav", time_ratio: 0.5) }
        .to raise_error(Muscript::Audio::Error, %r{audio file not found: stems/nope\.wav})
    end

    it "0以下や無限大の比率は受け取らない" do
      with_source do |path|
        expect { described_class.process(path, time_ratio: 0) }
          .to raise_error(described_class::Error, /invalid time ratio/)
        expect { described_class.process(path, time_ratio: Float::INFINITY) }
          .to raise_error(described_class::Error, /invalid time ratio/)
      end
    end

    describe "伸縮", :ffmpeg, :rubberband do
      it "比率どおりのサンプル数になる（グリッドに乗るのはここが正確だから）" do
        with_source(seconds: 1.0) do |path|
          expect(frames(described_class.process(path, time_ratio: 0.5))).to eq 22_050
          expect(frames(described_class.process(path, time_ratio: 2.0))).to eq 88_200
          expect(frames(described_class.process(path, time_ratio: 140 / 174.0)))
            .to eq (Muscript::SAMPLE_RATE * 140 / 174.0).round
        end
      end

      it "速さを変えても音の高さは変わらない" do
        with_source(seconds: 1.0, freq: 440) do |path|
          clip = Muscript::Audio.load(described_class.process(path, time_ratio: 0.5))

          expect(amplitude_at(clip.left, 440)).to be > 0.3
          expect(amplitude_at(clip.left, 880)).to be < 0.05 # 倍速再生ではない
        end
      end
    end

    describe "ピッチシフト", :ffmpeg, :rubberband do
      it "半音単位で音の高さだけを動かし、長さは変えない" do
        with_source(seconds: 1.0, freq: 440) do |path|
          clip = Muscript::Audio.load(described_class.process(path, semitones: 12))

          expect(clip.length).to eq Muscript::SAMPLE_RATE
          expect(amplitude_at(clip.left, 880)).to be > 0.3
          expect(amplitude_at(clip.left, 440)).to be < 0.05
        end
      end

      it "マイナスなら下がる" do
        with_source(seconds: 1.0, freq: 440) do |path|
          clip = Muscript::Audio.load(described_class.process(path, semitones: -12))

          expect(amplitude_at(clip.left, 220)).to be > 0.3
        end
      end

      it "伸縮とピッチシフトはrubberband1回で一緒に掛ける" do
        with_source(seconds: 1.0, freq: 440) do |path|
          clip = Muscript::Audio.load(described_class.process(path, time_ratio: 0.5, semitones: 12))

          expect(clip.length).to eq 22_050
          expect(amplitude_at(clip.left, 880)).to be > 0.3
        end
      end
    end

    describe "キャッシュ", :ffmpeg, :rubberband do
      it "同じ素材・同じ比率なら二度目は計算し直さない" do
        with_source do |path|
          first = described_class.process(path, time_ratio: 0.5)
          written_at = File.mtime(first)

          expect(described_class.process(path, time_ratio: 0.5)).to eq first
          expect(File.mtime(first)).to eq written_at
        end
      end

      it "二度目はrubberbandを呼ばない（本当に再利用している）" do
        with_source do |path, dir|
          cached = described_class.process(path, time_ratio: 0.5)
          # 呼ばれたら必ず落ちる偽物に差し替える。版だけ本物と同じにして、キャッシュを当てる。
          stub_const("Muscript::Warp::RUBBERBAND", fake_rubberband(dir, version: described_class.version))

          expect(described_class.process(path, time_ratio: 0.5)).to eq cached
        end
      end

      it "rubberbandの版が変われば別のキャッシュになる（エンジンが変われば音も変わる）" do
        with_source do |path, dir|
          described_class.process(path, time_ratio: 0.5)
          stub_const("Muscript::Warp::RUBBERBAND", fake_rubberband(dir, version: "99.0.0"))

          # 版が違うのでキャッシュに当たらず、伸ばし直そうとして偽物が落ちる
          expect { described_class.process(path, time_ratio: 0.5) }
            .to raise_error(described_class::Error, /rubberband failed/)
        end
      end

      it "比率や半音が違えば別のファイルになる" do
        with_source do |path|
          a = described_class.process(path, time_ratio: 0.5)
          b = described_class.process(path, time_ratio: 0.6)
          c = described_class.process(path, time_ratio: 0.5, semitones: 2)

          expect([a, b, c].uniq.length).to eq 3
        end
      end

      it "中身が1バイトでも違う素材は別のファイルになる（内容アドレス）" do
        in_tmpdir do |dir|
          a = Muscript::Wav.write(File.join(dir, "a.wav"), sine(440, 0.2), sine(440, 0.2))
          b = Muscript::Wav.write(File.join(dir, "b.wav"), sine(441, 0.2), sine(441, 0.2))

          expect(described_class.process(a, time_ratio: 0.5))
            .not_to eq described_class.process(b, time_ratio: 0.5)
        end
      end

      it "同じ中身なら名前が違っても同じキャッシュを使う" do
        in_tmpdir do |dir|
          wave = sine(440, 0.2)
          a = Muscript::Wav.write(File.join(dir, "a.wav"), wave, wave)
          b = Muscript::Wav.write(File.join(dir, "amen-140.wav"), wave, wave)

          expect(described_class.process(a, time_ratio: 0.5))
            .to eq described_class.process(b, time_ratio: 0.5)
        end
      end

      it "キャッシュディレクトリの下にだけ書く" do
        with_source do |path|
          cached = described_class.process(path, time_ratio: 0.5)

          expect(cached).to start_with described_class::CACHE_DIR
          expect(File.extname(cached)).to eq ".wav"
        end
      end

      it "途中で落ちたら半端なファイルを残さない" do
        with_source do |path, dir|
          stub_const("Muscript::Warp::RUBBERBAND", fake_rubberband(dir))

          expect { described_class.process(path, time_ratio: 0.5) }
            .to raise_error(described_class::Error, /rubberband failed.+boom/m)
          expect(Dir.glob(File.join(described_class::CACHE_DIR, "**", "*")).select { File.file?(_1) }).to be_empty
        end
      end
    end

    describe "rubberbandが無い時" do
      it "入れ方を教えて落ちる" do
        with_source do |path|
          stub_const("Muscript::Warp::RUBBERBAND", "muscript-no-such-rubberband")

          expect { described_class.process(path, time_ratio: 0.5) }
            .to raise_error(described_class::Error, /rubberband not found.+brew install rubberband/m)
        end
      end

      it "R3の無い古い版は、要る版を言って落ちる" do
        with_source do |path, dir|
          stub_const("Muscript::Warp::RUBBERBAND", fake_rubberband(dir, version: "2.0.2"))

          expect { described_class.process(path, time_ratio: 0.5) }
            .to raise_error(described_class::Error, /rubberband 2\.0\.2 is too old.+R3/m)
        end
      end
    end
  end

  describe ".available? / .version" do
    it "この環境のrubberbandが使えるかを返す" do
      expect(described_class.available?).to be Muscript::SpecHelpers::RUBBERBAND_AVAILABLE
    end

    it "実行ファイルが無ければ false / nil" do
      stub_const("Muscript::Warp::RUBBERBAND", "muscript-no-such-rubberband")

      expect(described_class.available?).to be false
      expect(described_class.version).to be_nil
    end

    it "R3の無い古い版は使えない扱いにする" do
      in_tmpdir do |dir|
        stub_const("Muscript::Warp::RUBBERBAND", fake_rubberband(dir, version: "2.0.2"))

        expect(described_class.version).to eq "2.0.2"
        expect(described_class.available?).to be false
      end
    end
  end
end
