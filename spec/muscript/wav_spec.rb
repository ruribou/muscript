RSpec.describe Muscript::Wav do
  describe ".write" do
    it "16bit / 2ch / 44.1kHz のPCMヘッダを書く" do
      in_tmpdir do |dir|
        path = File.join(dir, "a.wav")
        described_class.write(path, [0.0] * 10, [0.0] * 10)

        wav = read_wav(path)
        expect(wav).to include(
          audio_format: 1,     # PCM
          channels: 2,
          sample_rate: 44_100,
          bits: 16,
          block_align: 4,      # 2ch * 2byte
          byte_rate: 176_400,  # 44100 * 4
        )
      end
    end

    it "ヘッダのサイズをデータ長と一致させる" do
      in_tmpdir do |dir|
        path = described_class.write(File.join(dir, "a.wav"), [0.0] * 100, [0.0] * 100)

        wav = read_wav(path)
        expect(wav[:data_size]).to eq 100 * 2 * 2
        expect(wav[:riff_size]).to eq 36 + wav[:data_size]
        expect(File.size(path)).to eq 44 + wav[:data_size]
      end
    end

    it "LとRを交互に並べる" do
      in_tmpdir do |dir|
        path = described_class.write(File.join(dir, "a.wav"), [1.0, 0.0], [0.0, -1.0])

        wav = read_wav(path)
        expect(wav[:left]).to eq [32_767, 0]
        expect(wav[:right]).to eq [0, -32_767]
      end
    end

    it "Floatを16bit整数に変換する" do
      in_tmpdir do |dir|
        path = described_class.write(File.join(dir, "a.wav"), [0.5, -0.5], [0.0, 0.0])
        expect(read_wav(path)[:left]).to eq [16_384, -16_384]
      end
    end

    it "-1.0..1.0の外はクリップして壊れた値を書かない" do
      in_tmpdir do |dir|
        path = described_class.write(File.join(dir, "a.wav"), [5.0, -5.0], [2.0, -2.0])

        wav = read_wav(path)
        expect(wav[:left]).to eq [32_767, -32_767]
        expect(wav[:right]).to eq [32_767, -32_767]
      end
    end

    it "sample_rateを差し替えられる" do
      in_tmpdir do |dir|
        path = described_class.write(File.join(dir, "a.wav"), [0.0], [0.0], sample_rate: 48_000)

        wav = read_wav(path)
        expect(wav[:sample_rate]).to eq 48_000
        expect(wav[:byte_rate]).to eq 192_000
      end
    end

    it "無い階層のディレクトリを作ってから書く" do
      in_tmpdir do |dir|
        path = File.join(dir, "deep/er/still/a.wav")
        expect(described_class.write(path, [0.0], [0.0])).to eq path
        expect(File).to exist(path)
      end
    end

    it "同じ波形からは同じバイト列を書く" do
      in_tmpdir do |dir|
        left  = Array.new(500) { |i| Math.sin(i * 0.01) }
        right = Array.new(500) { |i| Math.cos(i * 0.01) }

        a = described_class.write(File.join(dir, "a.wav"), left, right)
        b = described_class.write(File.join(dir, "b.wav"), left, right)
        expect(File.binread(a)).to eq File.binread(b)
      end
    end
  end
end
