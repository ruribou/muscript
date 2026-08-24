require "open3"

# 「イントロ(ドラム無し) → ドロップ(全トラック)」の受け入れテスト。
# 曲の構造がそのまま音の並びになっているかを、小節ごとの音量で見る。
RSpec.describe "examples/arrange.rb" do
  let(:repo_root) { File.expand_path("../..", __dir__) }
  let(:project_bpm) { 174 }

  # 例は出力先を引数で受け取れる。
  def run_example(out_path)
    out, err, status = Open3.capture3("ruby", "examples/arrange.rb", out_path, chdir: repo_root)
    raise "examples/arrange.rb failed: #{err}" unless status.success?

    [out, err]
  end

  def frames_for(bars) = (bars * 4 * 60.0 / project_bpm * Muscript::SAMPLE_RATE).round

  # その小節でいちばん大きく鳴っている音。何が入って何が抜けたかを、これで見る。
  def bar_peak(samples, bar) = peak_of(samples[frames_for(bar - 1), frames_for(1)])

  it "24小節（イントロ8 + ドロップ16）+ 余韻の長さになる" do
    in_tmpdir do |dir|
      out_path = File.join(dir, "arrange.wav")
      out, err = run_example(out_path)

      expect(err).to be_empty
      expect(out).to match(/^Arrange Test \| 4 tracks \| 2 sections \| .+ -> #{Regexp.escape(out_path)}$/)

      wav = read_wav(out_path)
      expect(wav[:channels]).to eq 2
      expect(wav[:left].length)
        .to be_within(2).of(frames_for(24) + (Muscript::SAMPLE_RATE * 0.5).to_i)
    end
  end

  it "イントロにドラムは無く、9小節目のドロップで全トラックが入る" do
    in_tmpdir do |dir|
      out_path = File.join(dir, "arrange.wav")
      run_example(out_path)
      left = read_wav(out_path)[:left]

      intro = (1..7).map { |bar| bar_peak(left, bar) }
      drop  = (9..24).map { |bar| bar_peak(left, bar) }

      expect(intro.max).to be < drop.min / 2 # イントロは静か（パッドだけ）
      expect(intro.min).to be > 0.05         # でも無音ではない
      expect(drop.min).to be > 0.5           # ドロップは最後まで鳴り続ける
    end
  end

  it "イントロの最後の1小節にフィルが入る（ドロップの合図）" do
    in_tmpdir do |dir|
      out_path = File.join(dir, "arrange.wav")
      run_example(out_path)
      left = read_wav(out_path)[:left]

      expect(bar_peak(left, 8)).to be > bar_peak(left, 7) * 2 # 8小節目だけ跳ねる
      expect(bar_peak(left, 8)).to be < bar_peak(left, 9)     # ドロップよりは小さい
    end
  end

  it "何度レンダリングしても同じWAVになる" do
    in_tmpdir do |dir|
      a = File.join(dir, "a.wav")
      b = File.join(dir, "b.wav")
      run_example(a)
      run_example(b)

      expect(File.binread(a)).to eq File.binread(b)
    end
  end
end
