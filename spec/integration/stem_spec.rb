require "open3"

# ステムが素材として鳴ることの受け入れテスト。
# 「手持ちのWAVを1本 stems/ に置き、gain/pan付きでレンダリングできる」を確かめる。
RSpec.describe "examples/stem.rb", :ffmpeg do
  let(:repo_root) { File.expand_path("../..", __dir__) }

  # 例は「ステムの置き場所」と「出力先」を引数で受け取れる。specは一時ディレクトリで走らせる。
  def run_example(stems_dir, out_path)
    out, err, status = Open3.capture3("ruby", "examples/stem.rb", stems_dir, out_path, chdir: repo_root)
    raise "examples/stem.rb failed: #{err}" unless status.success?

    [out, err]
  end

  # 手持ちのステムの代わり。左右で中身の違うステレオWAVを1本置く。
  def place_stem(dir, name: "vocals.wav")
    Muscript::Wav.write(File.join(dir, name), sine(440, 1.0, amplitude: 0.5), sine(660, 1.0, amplitude: 0.5))
  end

  it "stems/ に置いたWAVをgain/pan付きでレンダリングする" do
    in_tmpdir do |dir|
      place_stem(dir)
      out_path = File.join(dir, "mix", "stem.wav")
      out, err = run_example(dir, out_path)

      expect(err).to be_empty
      expect(out).to match(/\AStem Remix \| 1 tracks \| 1\.50s \| peak .+ -> #{Regexp.escape(out_path)}\n\z/)

      wav = read_wav(out_path)
      expect(wav[:channels]).to eq 2
      expect(wav[:sample_rate]).to eq 44_100
      expect(wav[:left].length / wav[:sample_rate].to_f).to be_within(0.01).of(1.5) # 1秒 + 余韻0.5秒
    end
  end

  it "ステムの左右をそのまま通し、panで片側だけを絞る" do
    in_tmpdir do |dir|
      place_stem(dir)
      out_path = File.join(dir, "mix", "stem.wav")
      run_example(dir, out_path)

      wav = read_wav(out_path)
      left  = wav[:left].map { |s| s / 32_767.0 }
      right = wav[:right].map { |s| s / 32_767.0 }

      # gain -4dB / pan -0.25 → 左は素通し、右は0.75倍
      expect(peak_of(wav[:left])).to be_within(0.01).of(0.5 * 10**(-4 / 20.0))
      expect(peak_of(wav[:right])).to be_within(0.01).of(0.5 * 10**(-4 / 20.0) * 0.75)
      expect(amplitude_at(left, 440)).to be > amplitude_at(left, 660)   # 左は440Hzのまま
      expect(amplitude_at(right, 660)).to be > amplitude_at(right, 440) # 右は660Hzのまま
    end
  end

  it "mp3やflacでもそのまま読める（形式を選ばない）" do
    in_tmpdir do |dir|
      source = place_stem(dir, name: "source.wav")
      transcode(source, File.join(dir, "vocals.flac"))
      File.delete(source)

      out, = run_example(dir, File.join(dir, "mix", "stem.wav"))
      expect(out).to match(/Stem Remix \| 1 tracks \| 1\.50s/)
    end
  end

  it "ステムが無ければデモ用の素材を書き出してから鳴らす" do
    in_tmpdir do |dir|
      out, err = run_example(dir, File.join(dir, "mix", "stem.wav"))

      expect(err).to be_empty
      expect(Dir.children(dir)).to include("demo-drums.wav", "demo-bass.wav")
      expect(out).to match(/Stem Remix \| 2 tracks \|/)
      expect(peak_of(read_wav(File.join(dir, "mix", "stem.wav"))[:left])).to be > 0.1 # 無音ではない
    end
  end

  it "同じステムからは同じWAVを書く（決定論）" do
    in_tmpdir do |dir|
      place_stem(dir)
      a = File.join(dir, "mix", "a.wav")
      b = File.join(dir, "mix", "b.wav")
      run_example(dir, a)
      run_example(dir, b)

      expect(File.binread(a)).to eq File.binread(b)
    end
  end
end
