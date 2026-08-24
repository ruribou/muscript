RSpec.describe Muscript::Stem do
  # 素材の代わり。1秒 = 140BPMなら 2拍と1/3 ぶんの、ただのサイン波。
  def with_stem(seconds: 1.0, freq: 440)
    in_tmpdir do |dir|
      wave = sine(freq, seconds)
      yield Muscript::Wav.write(File.join(dir, "loop.wav"), wave, wave)
    end
  end

  def resolved_length(stem, **) = stem.resolve(**).length

  it "テンポを知らない素材も作れる（そのまま鳴らすだけの素材）" do
    stem = described_class.new("stems/x.wav")

    expect(stem.bpm).to be_nil
    expect(stem).to be_warp
    expect(stem.clip).to be_nil
  end

  it "0以下のBPMは受け取らない" do
    expect { described_class.new("stems/x.wav", bpm: 0) }
      .to raise_error(ArgumentError, /bpm must be positive/)
    expect { described_class.new("stems/x.wav", bpm: -140) }
      .to raise_error(ArgumentError, /bpm must be positive/)
  end

  describe "#resolve", :ffmpeg do
    it "テンポを知らない素材はそのまま読む" do
      with_stem do |path|
        expect(resolved_length(described_class.new(path), project_bpm: 174)).to eq Muscript::SAMPLE_RATE
      end
    end

    it "warp: false なら、テンポを知っていても伸ばさない" do
      with_stem do |path|
        stem = described_class.new(path, bpm: 140, warp: false)

        expect(stem).not_to be_warp
        expect(resolved_length(stem, project_bpm: 174)).to eq Muscript::SAMPLE_RATE
      end
    end

    it "揃え先と同じテンポなら伸ばさない" do
      with_stem do |path|
        expect(resolved_length(described_class.new(path, bpm: 174), project_bpm: 174))
          .to eq Muscript::SAMPLE_RATE
      end
    end

    it "読み込んだClipを持つ" do
      with_stem(seconds: 0.25) do |path|
        stem = described_class.new(path)
        stem.resolve(project_bpm: 174)

        expect(stem.clip).to be_a Muscript::Audio::Clip
        expect(stem.clip.duration).to be_within(0.001).of(0.25)
      end
    end

    it "無いファイルは読む前に落とす" do
      expect { described_class.new("stems/nope.wav").resolve(project_bpm: 174) }
        .to raise_error(Muscript::Audio::Error, /audio file not found/)
    end

    describe "playback_bpm（slice / loop の「1小節」の長さを決めるテンポ）" do
      it "テンポを教えていない素材は、曲のテンポに乗っているものとみなす" do
        with_stem do |path|
          stem = described_class.new(path)
          stem.resolve(project_bpm: 174)

          expect(stem.playback_bpm).to eq 174.0
        end
      end

      it "warp: false なら素材のテンポのまま" do
        with_stem do |path|
          stem = described_class.new(path, bpm: 140, warp: false)
          stem.resolve(project_bpm: 174)

          expect(stem.playback_bpm).to eq 140.0
        end
      end

      it "揃えたなら揃えた先のテンポ", :rubberband do
        with_stem do |path|
          stem = described_class.new(path, bpm: 140)
          stem.resolve(project_bpm: 174)

          expect(stem.playback_bpm).to eq 174.0
        end
      end

      it "warp_to があればそちらのテンポ", :rubberband do
        with_stem do |path|
          stem = described_class.new(path, bpm: 140)
          stem.resolve(project_bpm: 174, warp_to: 87)

          expect(stem.playback_bpm).to eq 87.0
        end
      end
    end

    describe "edits" do
      # 240BPMなら1小節=1秒。1秒の素材がちょうど1小節ぶんになる。
      it "読んだあとに、書いた順で掛ける" do
        with_stem do |path|
          edits = [Muscript::Edit.slice(beats: 2), Muscript::Edit.loop(times: 3)]

          expect(resolved_length(described_class.new(path), project_bpm: 240, edits:))
            .to eq (Muscript::SAMPLE_RATE * 0.5 * 3).round
        end
      end

      it "warp: false のときは素材のテンポの小節で切る" do
        with_stem(seconds: 4 * 60.0 / 140) do |path|
          stem = described_class.new(path, bpm: 140, warp: false)

          expect(resolved_length(stem, project_bpm: 174, edits: [Muscript::Edit.slice(bars: 1)]))
            .to eq (4 * 60.0 / 140 * Muscript::SAMPLE_RATE).round
        end
      end

      it "素材より長く切ろうとしたら、素材の長さを教えて落ちる" do
        with_stem do |path|
          expect { described_class.new(path).resolve(project_bpm: 240, edits: [Muscript::Edit.slice(bars: 4)]) }
            .to raise_error(ArgumentError, /is 1 bars at 240 BPM/)
        end
      end
    end

    describe "warp", :rubberband do
      it "揃えたあとの小節で切る（切るのは伸ばした後）" do
        with_stem(seconds: 4 * 60.0 / 140) do |path|
          stem = described_class.new(path, bpm: 140)

          expect(resolved_length(stem, project_bpm: 174, edits: [Muscript::Edit.slice(bars: 1)]))
            .to eq (4 * 60.0 / 174 * Muscript::SAMPLE_RATE).round
        end
      end

      it "素材のテンポをプロジェクトのテンポに合わせる" do
        with_stem do |path|
          expect(resolved_length(described_class.new(path, bpm: 140), project_bpm: 174))
            .to eq (Muscript::SAMPLE_RATE * 140 / 174.0).round
        end
      end

      it "warp_to があれば、プロジェクトのテンポより優先する（半テン/倍テン）" do
        with_stem do |path|
          expect(resolved_length(described_class.new(path, bpm: 140), project_bpm: 174, warp_to: 87))
            .to eq (Muscript::SAMPLE_RATE * 140 / 87.0).round
        end
      end

      it "テンポの違う素材どうしが、同じ小節数で同じ長さになる" do
        in_tmpdir do |dir|
          # どちらも1小節ぶんの素材。長さは違う(140BPMで1.71秒 / 90BPMで2.67秒)。
          a = Muscript::Wav.write(File.join(dir, "a.wav"), *([sine(440, 4 * 60.0 / 140)] * 2))
          b = Muscript::Wav.write(File.join(dir, "b.wav"), *([sine(330, 4 * 60.0 / 90)] * 2))

          lengths = [described_class.new(a, bpm: 140), described_class.new(b, bpm: 90)]
                    .map { resolved_length(_1, project_bpm: 174) }

          expect(lengths.uniq.length).to eq 1
          expect(lengths.first).to be_within(1).of(4 * 60.0 / 174 * Muscript::SAMPLE_RATE)
        end
      end

      it "半音だけ動かす時は長さを変えない" do
        with_stem(freq: 440) do |path|
          clip = described_class.new(path).resolve(project_bpm: 174, semitones: 12)

          expect(clip.length).to eq Muscript::SAMPLE_RATE
          expect(amplitude_at(clip.left, 880)).to be > 0.3
        end
      end

      it "warp_to を書いたのに素材のテンポが分からなければ、書き方を教えて落ちる" do
        with_stem do |path|
          expect { described_class.new(path).resolve(project_bpm: 174, warp_to: 87) }
            .to raise_error(ArgumentError, /warp_to 87 needs the source tempo.+bpm: 140/m)
        end
      end
    end
  end
end
