require "open3"

# 「素材の一部を切り出して、繰り返して並べる」の受け入れテスト。
# 12小節の素材(1小節ごとに音が変わる)の5小節目からの8小節が、4回ぶん並んで32小節になる。
RSpec.describe "examples/clip.rb", :ffmpeg do
  let(:repo_root) { File.expand_path("../..", __dir__) }
  let(:project_bpm) { 174 }
  let(:scale) { %w[C3 D3 E3 G3 A3 C4 D4 E4 G4 A4 C5 D5] } # 素材の小節ごとの音

  # 例は「素材の置き場所」と「出力先」を引数で受け取れる。
  def run_example(stems_dir, out_path)
    out, err, status = Open3.capture3("ruby", "examples/clip.rb", stems_dir, out_path, chdir: repo_root)
    raise "examples/clip.rb failed: #{err}" unless status.success?

    [out, err]
  end

  def frames_for(bars) = (bars * 4 * 60.0 / project_bpm * Muscript::SAMPLE_RATE).round

  # 指定した小節の真ん中あたりだけを取り出す(音の切れ目とエンベロープを避ける)。
  def bar_window(samples, bar)
    samples[frames_for(bar) + (frames_for(1) * 0.2).to_i, (frames_for(1) * 0.5).to_i]
  end

  # その窓でいちばん大きく鳴っている音。素材のどの小節が来ているかを、これで見る。
  def loudest_note(window) = scale.max_by { |n| amplitude_at(window, Muscript::Note.freq(n)) }

  it "32小節（8小節 × 4回）を1本にまとめる" do
    in_tmpdir do |dir|
      out_path = File.join(dir, "mix", "clip.wav")
      out, err = run_example(dir, out_path)

      expect(err).to be_empty
      expect(out).to match(/^Clip Test \| 2 tracks \| .+ -> #{Regexp.escape(out_path)}$/)

      wav = read_wav(out_path)
      expect(wav[:channels]).to eq 2
      # 32小節 + 余韻0.5秒。繰り返しの丸めで1サンプルずれることがある
      expect(wav[:left].length)
        .to be_within(2).of(frames_for(32) + (Muscript::SAMPLE_RATE * 0.5).to_i)
      expect(peak_of(wav[:left], wav[:right])).to be > 0.1 # 無音ではない
    end
  end

  it "頭に来るのは素材の5小節目（切り出しの位置）" do
    in_tmpdir do |dir|
      out_path = File.join(dir, "mix", "clip.wav")
      run_example(dir, out_path)
      window = bar_window(read_wav(out_path)[:left], 0)

      expect(loudest_note(window)).to eq scale[4]
      # 素材の1小節目の音は残っていない(頭から切ったのではない)
      expect(amplitude_at(window, Muscript::Note.freq(scale[4])))
        .to be > amplitude_at(window, Muscript::Note.freq(scale[0])) * 10
    end
  end

  it "8小節ごとに5小節目へ戻る（4回ぶん繰り返す）" do
    in_tmpdir do |dir|
      out_path = File.join(dir, "mix", "clip.wav")
      run_example(dir, out_path)
      left = read_wav(out_path)[:left]

      # 0,8,16,24小節目はスライスの頭(素材の5小節目)、7,31小節目はスライスの終わり(12小節目)
      expect([0, 8, 16, 24].map { |bar| loudest_note(bar_window(left, bar)) }).to eq [scale[4]] * 4
      expect([7, 31].map { |bar| loudest_note(bar_window(left, bar)) }).to eq [scale[11]] * 2
    end
  end
end
