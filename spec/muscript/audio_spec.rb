RSpec.describe Muscript::Audio do
  # 書いたWAVを読み戻す。muscript自身のWav.writeが「手持ちのファイル」の代わり。
  def with_source(left, right = left, sample_rate: Muscript::SAMPLE_RATE)
    in_tmpdir do |dir|
      path = Muscript::Wav.write(File.join(dir, "src.wav"), left, right, sample_rate:)
      yield path, dir
    end
  end

  describe ".load", :ffmpeg do
    it "書いたWAVをそのまま読み戻す（16bitの丸め誤差の範囲で一致）" do
      wave = sine(440, 0.2)

      with_source(wave) do |path|
        clip = described_class.load(path)

        expect(clip.length).to eq wave.length
        expect(max_diff(clip.left, wave)).to be < 1e-4 # 1/32767 ≒ 3.1e-5
        expect(clip.right).to eq clip.left
      end
    end

    it "左右を別のチャンネルとして読む" do
      left  = sine(440, 0.2, amplitude: 0.5)
      right = sine(880, 0.2, amplitude: 0.25)

      with_source(left, right) do |path|
        clip = described_class.load(path)

        expect(clip.left.map(&:abs).max).to be_within(0.001).of(0.5)
        expect(clip.right.map(&:abs).max).to be_within(0.001).of(0.25)
        expect(amplitude_at(clip.left, 440)).to be_within(0.01).of(0.5)
        expect(amplitude_at(clip.right, 880)).to be_within(0.01).of(0.25)
      end
    end

    it "64KiBずつ読んでも波形は繋がる（チャンクをまたぐ長さ）" do
      wave = sine(220, 2.0) # 約1.4MB。1チャンク(64KiB)には収まらない

      with_source(wave) do |path|
        clip = described_class.load(path)

        expect(clip.length).to eq wave.length
        expect(max_diff(clip.left, wave)).to be < 1e-4
      end
    end

    it "44.1kHz以外はffmpegに任せてリサンプルする" do
      wave = sine(440, 0.2, sample_rate: 22_050)

      with_source(wave, sample_rate: 22_050) do |path|
        clip = described_class.load(path)

        expect(clip.sample_rate).to eq Muscript::SAMPLE_RATE
        expect(clip.length).to be_within(2).of(wave.length * 2)
      end
    end

    it "リサンプルしても音の高さは変わらない" do
      with_source(sine(440, 0.2, sample_rate: 32_000), sample_rate: 32_000) do |path|
        clip = described_class.load(path)

        expect(amplitude_at(clip.left, 440)).to be_within(0.02).of(0.5)
        expect(amplitude_at(clip.left, 606)).to be < 0.02 # 32k→44.1kの比でずれた音は出ていない
      end
    end

    it "形式を選ばない（flac/AIFFでも読める）" do
      wave = sine(440, 0.2)

      with_source(wave) do |path, dir|
        %w[flac aiff].each do |format|
          clip = described_class.load(transcode(path, File.join(dir, "src.#{format}")))

          expect(clip.length).to eq(wave.length), "#{format} の長さが違う"
          expect(max_diff(clip.left, wave)).to be < 1e-4, "#{format} の波形が違う"
        end
      end
    end

    it "モノラルの素材も左右に開いて読む（ffmpegの等パワー変換で-3dB）" do
      with_source(sine(440, 0.2)) do |path, dir|
        clip = described_class.load(transcode(path, File.join(dir, "mono.wav"), "-ac", "1"))

        expect(clip.right).to eq clip.left
        expect(amplitude_at(clip.left, 440)).to be_within(0.02).of(0.5 * Math.sqrt(0.5))
      end
    end

    it "長さとサンプルレートを持ったClipを返す" do
      with_source(sine(440, 0.5)) do |path|
        clip = described_class.load(path)

        expect(clip).to be_a Muscript::Audio::Clip
        expect(clip.path).to eq path
        expect(clip.duration).to be_within(0.001).of(0.5)
        expect(clip.sample_rate).to eq 44_100
      end
    end

    it "無いファイルは読む前に落とす" do
      expect { described_class.load("stems/nope.wav") }
        .to raise_error(described_class::Error, %r{audio file not found: stems/nope\.wav})
    end

    it "音声が入っていないファイルはffmpegの言い分を添えて落とす" do
      in_tmpdir do |dir|
        path = File.join(dir, "not-audio.txt")
        File.write(path, "これは音ではない")

        expect { described_class.load(path) }
          .to raise_error(described_class::Error, /ffmpeg failed to decode/)
      end
    end
  end

  describe ".load（ffmpegが無い時）" do
    it "入れ方を教えて落ちる" do
      with_source([0.0, 0.1]) do |path|
        stub_const("Muscript::Audio::FFMPEG", "muscript-no-such-ffmpeg")

        expect { described_class.load(path) }
          .to raise_error(described_class::Error, /ffmpeg not found.+brew install ffmpeg/m)
      end
    end
  end

  describe ".available?" do
    it "ffmpegが呼べるかを返す" do
      expect(described_class.available?).to be Muscript::SpecHelpers::FFMPEG_AVAILABLE
    end

    it "実行ファイルが無ければfalse" do
      stub_const("Muscript::Audio::FFMPEG", "muscript-no-such-ffmpeg")
      expect(described_class.available?).to be false
    end
  end
end
